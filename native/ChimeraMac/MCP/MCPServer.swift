import Foundation
import Network

@MainActor
protocol MCPRouting {
    var definitions: [[String: Any]] { get }
    func call(_ name: String, arguments: [String: Any]) async -> [String: Any]
}

protocol HeadStreamConnection: AnyObject {
    func sendHeadStreamHeaders()
    func sendHeadStreamData(_ data: Data)
}

@MainActor
final class HeadStreamService {
    private var connections: [ObjectIdentifier: any HeadStreamConnection] = [:]
    private let encoder = JSONEncoder()

    var clientCount: Int { connections.count }

    func add(_ connection: any HeadStreamConnection) {
        connections[ObjectIdentifier(connection)] = connection
    }

    func remove(_ connection: any HeadStreamConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }

    func publish(_ frame: HeadTelemetryFrame) {
        guard !connections.isEmpty else { return }
        do {
            var data = try encoder.encode(frame)
            data.append(0x0a)
            for connection in connections.values {
                connection.sendHeadStreamData(data)
            }
        } catch {
            print("CHIMERA head stream encoding failed: \(error)")
        }
    }
}

@MainActor
final class MCPServer {
    let port: Int

    private let serverName: String
    private let router: any MCPRouting
    private let headStream: HeadStreamService?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: MCPConnection] = [:]

    init(port: Int, serverName: String = "chimera-mac", router: any MCPRouting, headStream: HeadStreamService? = nil) {
        self.port = port
        self.serverName = serverName
        self.router = router
        self.headStream = headStream
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let endpointPort = NWEndpoint.Port(integerLiteral: UInt16(clamping: port))
            let listener = try NWListener(using: parameters, on: endpointPort)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("CHIMERA MCP listener failed on \(self.port): \(error)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: DispatchQueue(label: "org.chimera.mcp.listener.\(port)"))
            self.listener = listener
            print("CHIMERA MCP listening on http://127.0.0.1:\(port)/mcp")
        } catch {
            print("CHIMERA MCP listener failed on \(port): \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        let box = MCPConnection(connection)
        let id = ObjectIdentifier(box)
        connections[id] = box
        box.onClose = { [weak self] in
            Task { @MainActor in
                self?.connections.removeValue(forKey: id)
                self?.headStream?.remove(box)
            }
        }
        box.onRequest = { [weak self] data, box in
            guard let self else { return }
            Task { @MainActor in
                await self.process(data, connection: box)
            }
        }
        if headStream != nil {
            box.onHeadStream = { [weak self] box in
                Task { @MainActor in self?.headStream?.add(box) }
            }
        }
        box.start()
    }

    private func process(_ data: Data, connection: MCPConnection) async {
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  request["jsonrpc"] as? String == "2.0",
                  let method = request["method"] as? String else {
                connection.sendJSON(status: 400, payload: Self.error(id: nil, code: -32600, message: "Invalid JSON-RPC request"))
                return
            }
            let id = request["id"]
            if id == nil && method.hasPrefix("notifications/") {
                connection.sendEmpty(status: 202)
                return
            }
            let params = request["params"] as? [String: Any] ?? [:]
            switch method {
            case "initialize":
                connection.sendJSON(payload: Self.result(id: id, value: [
                    "protocolVersion": "2025-06-18",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": serverName, "version": "0.1.0"],
                    "instructions": "Control CHIMERA through the tools advertised by this application. Audio starts on the first sounding tool call when supported."
                ]))
            case "ping":
                connection.sendJSON(payload: Self.result(id: id, value: [:]))
            case "tools/list":
                connection.sendJSON(payload: Self.result(id: id, value: ["tools": router.definitions]))
            case "resources/list":
                connection.sendJSON(payload: Self.result(id: id, value: ["resources": []]))
            case "prompts/list":
                connection.sendJSON(payload: Self.result(id: id, value: ["prompts": []]))
            case "tools/call":
                guard let name = params["name"] as? String else {
                    connection.sendJSON(payload: Self.error(id: id, code: -32602, message: "Missing tool name"))
                    return
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let output = await router.call(name, arguments: arguments)
                connection.sendJSON(payload: Self.result(id: id, value: output))
            default:
                connection.sendJSON(payload: Self.error(id: id, code: -32601, message: "Method not found: \(method)"))
            }
        } catch {
            connection.sendJSON(status: 400, payload: Self.error(id: nil, code: -32700, message: "Parse error: \(error.localizedDescription)"))
        }
    }

    private static func result(id: Any?, value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value]
    }

    private static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

private final class MCPConnection: HeadStreamConnection {
    let connection: NWConnection
    var onRequest: ((Data, MCPConnection) -> Void)?
    var onHeadStream: ((MCPConnection) -> Void)?
    var onClose: (() -> Void)?

    private var buffer = Data()
    private var closed = false
    private var streaming = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "org.chimera.mcp.connection"))
        receive()
    }

    func sendJSON(status: Int = 200, payload: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            send(status: status, contentType: "application/json", body: data)
        } catch {
            sendEmpty(status: 500)
        }
    }

    func sendEmpty(status: Int) {
        send(status: status, contentType: nil, body: Data())
    }

    func sendHeadStreamHeaders() {
        guard !closed, !streaming else { return }
        streaming = true
        sendRaw(Data("HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n".utf8))
    }

    func sendHeadStreamData(_ data: Data) {
        guard streaming else { return }
        sendRaw(data)
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if error != nil || complete {
                self.close()
                return
            }
            self.parseRequests()
            self.receive()
        }
    }

    private func parseRequests() {
        while let headerRange = buffer.range(of: Data([13, 10, 13, 10])) {
            let header = String(decoding: buffer[..<headerRange.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ")
            var contentLength = 0
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            if contentLength > 1_048_576 {
                sendEmpty(status: 413)
                close()
                return
            }
            let bodyStart = headerRange.upperBound
            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength, limitedBy: buffer.endIndex)
            guard let bodyEnd else { return }
            let body = Data(buffer[bodyStart..<bodyEnd])
            buffer.removeSubrange(..<bodyEnd)
            guard request?.count == 3 else {
                sendEmpty(status: 400)
                continue
            }
            let path = request?[1].split(separator: "?").first
            if request?[0] == "GET", path == "/head/stream", onHeadStream != nil {
                sendHeadStreamHeaders()
                onHeadStream?(self)
                continue
            }
            guard request?[0] == "POST", path == "/mcp" else {
                sendEmpty(status: 404)
                continue
            }
            onRequest?(body, self)
        }
    }

    private func send(status: Int, contentType: String?, body: Data) {
        guard !closed, !streaming else { return }
        var header = "HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Length: \(body.count)\r\nConnection: keep-alive\r\n"
        if let contentType { header += "Content-Type: \(contentType)\r\n" }
        header += "MCP-Protocol-Version: 2025-06-18\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        sendRaw(response)
    }

    private func sendRaw(_ data: Data) {
        guard !closed else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.close() }
        })
    }

    private func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Content Too Large"
        default: return "Internal Server Error"
        }
    }
}

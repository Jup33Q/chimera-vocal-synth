import Foundation

@MainActor
final class RemoteHeadClient {
    var onFrame: ((HeadTelemetryFrame) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private struct Command {
        let name: String
        let arguments: [String: Any]
        let coalesceKey: String?
        let completion: ((Result<[String: Any], Error>) -> Void)?
    }

    private let baseURL = URL(string: "http://127.0.0.1:8647")!
    private let decoder = JSONDecoder()
    private var streamTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var commands: [Command] = []

    func start() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            await self?.streamLoop()
        }
    }

    func startAudio() async throws {
        await waitForCommands()
        _ = try await call("chimera_start", arguments: [:])
    }

    func currentStatus() async throws -> [String: Any] {
        await waitForCommands()
        return try await call("chimera_status", arguments: [:])
    }

    func playNote(midi: Int, duration: Double) async throws -> [String: Any] {
        await waitForCommands()
        return try await call("chimera_play_note", arguments: ["midi": midi, "duration": duration])
    }

    func speak(text: String, ipa: Bool, rate: Double, f0: Double) async throws -> [String: Any] {
        await waitForCommands()
        return try await call("chimera_speak", arguments: [
            "text": text,
            "ipa": ipa,
            "rate": rate,
            "f0": f0
        ])
    }

    func sing(notes: [SingNote], bpm: Double, vibrato: Double, title: String) async throws -> [String: Any] {
        try await request("chimera_sing", arguments: [
            "action": "play",
            "notes": try jsonObject(notes),
            "bpm": bpm,
            "vibrato": vibrato,
            "title": title
        ], coalesceKey: "sing-play")
    }

    func sing(song: DemoSong, vibrato: Double) async throws -> [String: Any] {
        try await request("chimera_sing", arguments: [
            "action": "play",
            "song": try jsonObject(song),
            "vibrato": vibrato
        ], coalesceKey: "sing-play")
    }

    func singNoteOn(_ syllable: Syllable, midi: Int, vibrato: Double) {
        guard let value = try? jsonObject(syllable) else { return }
        enqueue("chimera_sing", arguments: [
            "action": "note-on",
            "syllable": value,
            "midi": midi,
            "vibrato": vibrato
        ])
    }

    func singNoteOff(_ midi: Int) {
        enqueue("chimera_sing", arguments: ["action": "note-off", "midi": midi])
    }

    func stopSpeech() {
        enqueue("chimera_stop_speech", arguments: [:])
    }

    func stopSinging() {
        enqueue("chimera_stop_singing", arguments: [:], coalesceKey: "sing-stop")
    }

    func setSource(_ source: VoiceSource) {
        guard let values = try? jsonObject(source) else { return }
        enqueue("chimera_set_voice", arguments: ["source": values], coalesceKey: "source")
    }

    func setArtic(_ artic: HumanArtic) {
        guard let values = try? jsonObject(artic) else { return }
        enqueue("chimera_set_voice", arguments: ["artic": values], coalesceKey: "artic")
    }

    func setBody(_ body: BodyMix) {
        enqueue("chimera_set_voice", arguments: ["bodyMix": ["female": body.female, "child": body.child]], coalesceKey: "body")
    }

    func setWhisper(_ enabled: Bool) {
        enqueue("chimera_set_voice", arguments: ["whisper": enabled], coalesceKey: "whisper")
    }

    func noteOn(_ midi: Int) {
        enqueue("chimera_note_on", arguments: ["midi": midi])
    }

    func noteOff(_ midi: Int) {
        enqueue("chimera_note_off", arguments: ["midi": midi])
    }

    func setGate(_ on: Bool) {
        enqueue("chimera_set_gate", arguments: ["on": on])
    }

    func beatHit(_ id: String) {
        enqueue("chimera_beatbox", arguments: ["action": "hit", "sound": id])
    }

    func setBeat(steps: [BeatStep?]? = nil, bpm: Double? = nil, swing: Double? = nil, playing: Bool? = nil) {
        var arguments: [String: Any] = [
            "action": playing == true ? "play" : playing == false ? "stop" : "set"
        ]
        if let steps, let values = try? jsonObject(steps) { arguments["steps"] = values }
        if let bpm { arguments["bpm"] = bpm }
        if let swing { arguments["swing"] = swing }
        let coalesceKey = playing == nil ? (steps == nil ? "beat-transport" : "beat-steps") : nil
        enqueue("chimera_beatbox", arguments: arguments, coalesceKey: coalesceKey)
    }

    func stop() {
        enqueue("chimera_stop", arguments: [:])
    }

    private func request(_ name: String, arguments: [String: Any], coalesceKey: String?) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(name, arguments: arguments, coalesceKey: coalesceKey) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func enqueue(
        _ name: String,
        arguments: [String: Any],
        coalesceKey: String? = nil,
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        if let coalesceKey {
            let stale = commands.filter { $0.coalesceKey == coalesceKey }
            commands.removeAll { $0.coalesceKey == coalesceKey }
            for command in stale {
                command.completion?(.failure(CancellationError()))
            }
        }
        commands.append(Command(name: name, arguments: arguments, coalesceKey: coalesceKey, completion: completion))
        guard commandTask == nil else { return }
        commandTask = Task { [weak self] in
            await self?.drainCommands()
        }
    }

    private func drainCommands() async {
        while !commands.isEmpty {
            let command = commands.removeFirst()
            do {
                let result = try await call(command.name, arguments: command.arguments)
                command.completion?(.success(result))
            } catch {
                command.completion?(.failure(error))
                onError?(error.localizedDescription)
            }
        }
        commandTask = nil
        if !commands.isEmpty {
            commandTask = Task { [weak self] in
                await self?.drainCommands()
            }
        }
    }

    private func waitForCommands() async {
        while let commandTask {
            await commandTask.value
        }
    }

    private func streamLoop() async {
        while !Task.isCancelled {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: baseURL.appending(path: "head/stream"))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw ChimeraError(message: "Head telemetry returned a non-200 response.")
                }
                onConnection?(true)
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                    onFrame?(try decoder.decode(HeadTelemetryFrame.self, from: data))
                }
            } catch {
                if Task.isCancelled { break }
            }
            onConnection?(false)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func call(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ]
        var request = URLRequest(url: baseURL.appending(path: "mcp"))
        request.timeoutInterval = 4
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ChimeraError(message: "Head is unavailable on 127.0.0.1:8647.")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = object?["error"] as? [String: Any] {
            throw ChimeraError(message: error["message"] as? String ?? "Head rejected the control request.")
        }
        let result = object?["result"] as? [String: Any]
        if result?["isError"] as? Bool == true {
            let content = result?["content"] as? [[String: Any]]
            throw ChimeraError(message: content?.first?["text"] as? String ?? "Head rejected the control request.")
        }
        return result?["structuredContent"] as? [String: Any] ?? [:]
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
}

import Foundation

@MainActor
final class HeadToolRouter: MCPRouting {
    private let model: HeadModel
    private let instrumentRouter: MCPToolRouter

    init(model: HeadModel, instrument: InstrumentModel) {
        self.model = model
        instrumentRouter = MCPToolRouter(model: instrument, port: 8647)
    }

    var definitions: [[String: Any]] {
        instrumentRouter.definitions + headDefinitions
    }

    private let headDefinitions: [[String: Any]] = [
        headTool(
            name: "head_status",
            description: "Read the Head audio engine, live articulation, telemetry, stream clients and camera.",
            properties: [:]
        ),
        headTool(
            name: "head_select_source",
            description: "Retain P0 source-selection compatibility; Head now owns the single local audio engine.",
            properties: ["source": ["type": "string", "enum": ["auto", "play"], "default": "auto"]],
            required: ["source"]
        ),
        headTool(
            name: "head_set_camera",
            description: "Set orbit yaw, pitch and zoom, or reset the local camera without affecting audio.",
            properties: [
                "yaw": ["type": "number"],
                "pitch": ["type": "number", "minimum": -1.1, "maximum": 1.1],
                "zoom": ["type": "number", "minimum": 0.55, "maximum": 2.4],
                "reset": ["type": "boolean", "default": false]
            ]
        ),
        headTool(
            name: "head_set_visuals",
            description: "Enable or disable spring head animation and physical airflow particles without changing audio.",
            properties: ["animation": ["type": "boolean"], "particles": ["type": "boolean"]]
        ),
        headTool(
            name: "head_lkg",
            description: "Connect or disconnect the independent Looking Glass renderer using live Bridge calibration.",
            properties: ["action": ["type": "string", "enum": ["connect", "disconnect"]]],
            required: ["action"]
        ),
        headTool(
            name: "head_lkg_camera",
            description: "Adjust the LKG-only parallel camera array without moving the local Head camera.",
            properties: [
                "yaw": ["type": "number"],
                "pitch": ["type": "number", "minimum": -1.1, "maximum": 1.1],
                "zoom": ["type": "number", "minimum": 0.55, "maximum": 2.4],
                "fov": ["type": "number", "minimum": 12, "maximum": 90],
                "focus": ["type": "number", "minimum": 20, "maximum": 100],
                "parallax": ["type": "number", "minimum": 0, "maximum": 30]
            ]
        )
    ]

    func call(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        if !name.hasPrefix("head_") {
            return await instrumentRouter.call(name, arguments: arguments)
        }
        do {
            let value = try execute(name, arguments: arguments)
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ["content": [["type": "text", "text": text]], "structuredContent": value]
        } catch {
            return ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
        }
    }

    private func execute(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        switch name {
        case "head_status":
            return status()
        case "head_select_source":
            guard let source = arguments["source"] as? String, source == "auto" || source == "play" else {
                throw HeadModelError(message: "source must be auto or play.")
            }
            model.selectSource(source)
            return status()
        case "head_set_camera":
            if arguments["reset"] as? Bool == true { model.camera.reset() }
            if let yaw = (arguments["yaw"] as? NSNumber)?.doubleValue { model.camera.yaw = yaw }
            if let pitch = (arguments["pitch"] as? NSNumber)?.doubleValue { model.camera.pitch = min(1.1, max(-1.1, pitch)) }
            if let zoom = (arguments["zoom"] as? NSNumber)?.doubleValue { model.camera.zoom = min(2.4, max(0.55, zoom)) }
            return status()
        case "head_set_visuals":
            if let animation = arguments["animation"] as? Bool { model.animationEnabled = animation }
            if let particles = arguments["particles"] as? Bool { model.particlesEnabled = particles }
            return status()
        case "head_lkg":
            guard let action = arguments["action"] as? String else { throw HeadModelError(message: "action must be connect or disconnect.") }
            if action == "connect" {
                if !model.lkgConnected { model.toggleLKG() }
            } else if action == "disconnect" {
                if model.lkgConnected { model.toggleLKG() }
            } else {
                throw HeadModelError(message: "action must be connect or disconnect.")
            }
            return status()
        case "head_lkg_camera":
            model.setLKGCamera(
                yaw: (arguments["yaw"] as? NSNumber)?.doubleValue,
                pitch: (arguments["pitch"] as? NSNumber)?.doubleValue,
                zoom: (arguments["zoom"] as? NSNumber)?.doubleValue,
                fov: (arguments["fov"] as? NSNumber)?.doubleValue,
                focus: (arguments["focus"] as? NSNumber)?.doubleValue,
                parallax: (arguments["parallax"] as? NSNumber)?.doubleValue
            )
            return status()
        default:
            throw HeadModelError(message: "Unknown tool: \(name)")
        }
    }

    private func status() -> [String: Any] {
        let instrument = instrumentRouter.model
        let playing = instrument.isStarted && (
            instrument.hold || !instrument.heldNotes.isEmpty || instrument.beatPlaying ||
            instrument.playingSong != nil || instrument.telemetry.gate > 0.01
        )
        return [
            "state": instrument.frame == nil ? "Waiting" : playing ? "Live" : "Standby",
            "connection": "Local audio and model host",
            "sourceMode": model.sourceMode,
            "source": "head",
            "instanceID": instrument.instanceID,
            "projectID": instrument.projectID,
            "projectName": instrument.projectName,
            "playing": playing,
            "active": instrument.isStarted,
            "engineRunning": instrument.audioEngineRunning,
            "renderedFrames": instrument.audioRenderedFrames,
            "whisper": instrument.whisperEnabled,
            "voiced": instrument.source.voiced,
            "lastError": instrument.lastError ?? NSNull(),
            "beatStep": instrument.beatPlayhead,
            "f0": instrument.telemetry.f0,
            "gate": instrument.telemetry.gate,
            "outRms": instrument.telemetry.outRMS,
            "clock": instrument.telemetry.clock,
            "hasGeometry": instrument.frame != nil,
            "streamClients": instrument.headStreamClientCount,
            "animationEnabled": model.animationEnabled,
            "particlesEnabled": model.particlesEnabled,
            "lkg": [
                "connected": model.lkgConnected,
                "status": model.lkgStatus,
                "renderedFrames": model.lkgFrameCount,
                "hardwareVerified": model.lkgHardwareVerified,
                "fov": model.lkgFov,
                "focus": model.lkgFocus,
                "parallax": model.lkgParallax,
                "orientation": model.lkgOrientation
            ],
            "camera": ["yaw": model.camera.yaw, "pitch": model.camera.pitch, "zoom": model.camera.zoom],
            "mcp": "http://127.0.0.1:8647/mcp",
            "headStream": "http://127.0.0.1:8647/head/stream"
        ]
    }
}

struct HeadModelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func headTool(name: String, description: String, properties: [String: Any], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
    if !required.isEmpty { schema["required"] = required }
    return ["name": name, "description": description, "inputSchema": schema]
}

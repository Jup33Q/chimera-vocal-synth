import Foundation

@MainActor
final class MCPToolRouter: MCPRouting {
    let model: InstrumentModel
    private let port: Int
    private let allowedTools: Set<String>?

    init(model: InstrumentModel, port: Int = 8642, allowedTools: [String]? = nil) {
        self.model = model
        self.port = port
        self.allowedTools = allowedTools.map(Set.init)
    }

    var definitions: [[String: Any]] {
        guard let allowedTools else { return allDefinitions }
        return allDefinitions.filter { allowedTools.contains($0["name"] as? String ?? "") }
    }

    private let allDefinitions: [[String: Any]] = [
        tool(
            name: "chimera_status",
            description: "Read the current mode, body, audio state and live engine telemetry.",
            properties: [:]
        ),
        tool(
            name: "chimera_play_note",
            description: "Play a human voice note through the physical airway, then release it.",
            properties: [
                "midi": ["type": "integer", "minimum": 0, "maximum": 127, "description": "MIDI note number."],
                "duration": ["type": "number", "minimum": 0.05, "maximum": 30, "default": 1, "description": "Note length in seconds."]
            ],
            required: ["midi"]
        ),
        tool(
            name: "chimera_start",
            description: "Start the shared Head audio engine without opening the gate.",
            properties: [:]
        ),
        tool(
            name: "chimera_note_on",
            description: "Begin holding a MIDI note until chimera_note_off or chimera_stop.",
            properties: ["midi": ["type": "integer", "minimum": 0, "maximum": 127]],
            required: ["midi"]
        ),
        tool(
            name: "chimera_note_off",
            description: "Release a held MIDI note.",
            properties: ["midi": ["type": "integer", "minimum": 0, "maximum": 127]],
            required: ["midi"]
        ),
        tool(
            name: "chimera_speak",
            description: "Speak supplied text, or generate plain English with a local Ollama model and speak it.",
            properties: [
                "text": ["type": "string", "description": "Text to speak. Required unless generate is true."],
                "generate": ["type": "boolean", "default": false, "description": "Generate English text with Ollama before speaking."],
                "prompt": ["type": "string", "description": "Subject or writing instruction for Ollama."],
                "ollamaModel": ["type": "string", "description": "Installed Ollama model with completion support."],
                "ipa": ["type": "boolean", "default": false],
                "rate": ["type": "number", "minimum": 0.5, "maximum": 1.8, "default": 1],
                "f0": ["type": "number", "minimum": 40, "maximum": 1100, "description": "Optional baseline pitch in Hz."]
            ]
        ),
        tool(
            name: "chimera_stop_speech",
            description: "Stop the current speech plan without changing the sequencer or held notes.",
            properties: [:]
        ),
        tool(
            name: "chimera_sing",
            description: "Edit, generate or play an English lyric score through Head, or sing one legacy MIDI note.",
            properties: [
                "action": ["type": "string", "enum": ["play", "set", "generate", "stop", "note-on", "note-off"], "default": "play"],
                "lyrics": ["type": "string", "description": "English lyrics to distribute across the edited notes; never use prompt as lyrics."],
                "syllable": ["type": "object", "description": "Validated engine Syllable for MIDI note-on input."],
                "notes": ["type": "array", "description": "SingNote objects with id, midi, start and duration in beats, and one lyric syllable per note."],
                "song": ["type": "object", "description": "A DemoSong preset to play through the existing song planner."],
                "title": ["type": "string", "default": "Current score"],
                "bpm": ["type": "number", "minimum": 40, "maximum": 240, "default": 100],
                "generate": ["type": "boolean", "default": false, "description": "Generate and validate English lyrics with Ollama before editing or singing."],
                "prompt": ["type": "string", "description": "Subject or writing instruction for Ollama; never sung directly."],
                "ollamaModel": ["type": "string", "description": "Installed Ollama model with completion support."],
                "midi": ["type": "integer", "minimum": 0, "maximum": 127, "default": 60],
                "duration": ["type": "number", "minimum": 0.05, "maximum": 30, "default": 1],
                "vibrato": ["type": "number", "minimum": 0, "maximum": 100, "default": 35]
            ]
        ),
        tool(
            name: "chimera_stop_singing",
            description: "Stop the current song without changing speech, the beat sequencer or held notes.",
            properties: [:]
        ),
        tool(
            name: "chimera_beatbox",
            description: "Control the articulatory step sequencer or trigger one beatbox sound.",
            properties: [
                "action": ["type": "string", "enum": ["play", "stop", "hit", "set"]],
                "sound": ["type": "string", "description": "Sound id for hit, such as b, p, t, k, ts or m."],
                "steps": ["type": "array", "description": "Up to 128 steps; each item is null or a BeatStep object."],
                "bpm": ["type": "number", "minimum": 50, "maximum": 180],
                "swing": ["type": "number", "minimum": 0, "maximum": 0.7]
            ],
            required: ["action"]
        ),
        tool(
            name: "chimera_creature",
            description: "Select a creature, set its physical voice parameters and optionally play a named call.",
            properties: [
                "id": ["type": "string", "enum": ["songbird", "seal", "alligator", "elephant"], "default": "songbird"],
                "call": ["type": "string", "description": "Optional call id from the selected creature."],
                "params": ["type": "object", "additionalProperties": ["type": "number"]]
            ]
        ),
        tool(
            name: "chimera_set_voice",
            description: "Set mode, body and any human source or articulator parameters.",
            properties: [
                "mode": ["type": "string", "enum": ["play", "speak", "sing", "beatbox", "bestiary"]],
                "body": ["type": "string", "enum": ["male", "female", "child"]],
                "bodyMix": [
                    "type": "object",
                    "properties": ["female": ["type": "number", "minimum": 0, "maximum": 1], "child": ["type": "number", "minimum": 0, "maximum": 1]],
                    "additionalProperties": false
                ],
                "source": ["type": "object", "additionalProperties": true],
                "artic": ["type": "object", "additionalProperties": ["type": "number"]],
                "whisper": ["type": "boolean", "description": "Persistently whisper all Head controls until disabled."]
            ]
        ),
        tool(
            name: "chimera_set_gate",
            description: "Hold or release the current voice's breath gate.",
            properties: ["on": ["type": "boolean"]],
            required: ["on"]
        ),
        tool(
            name: "chimera_stop",
            description: "Stop speech, singing, calls, the sequencer and all held notes.",
            properties: [:]
        )
    ]

    func call(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        do {
            let value = try await execute(name, arguments: arguments)
            return success(value)
        } catch {
            return [
                "content": [["type": "text", "text": error.localizedDescription]],
                "isError": true
            ]
        }
    }

    private func execute(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        if let allowedTools, !allowedTools.contains(name) {
            throw ChimeraError(message: "Tool is not available in this application: \(name)")
        }
        switch name {
        case "chimera_status":
            return status()
        case "chimera_play_note":
            let midi = try requiredInt(arguments, key: "midi")
            let duration = boundedNumber(arguments, key: "duration", default: 1, range: 0.05...30)
            if model.isRemoteController {
                return try await model.remotePlayNote(midi: midi, duration: duration)
            }
            model.mode = .play
            model.noteOn(midi)
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            let soundingStatus = status()
            model.noteOff(midi)
            return ["played": midi, "duration": duration, "outRms": soundingStatus["outRms"] ?? 0, "telemetry": soundingStatus]
        case "chimera_start":
            model.startAudio()
            return ["audioRunning": model.isStarted]
        case "chimera_note_on":
            let midi = try requiredInt(arguments, key: "midi")
            model.noteOn(midi)
            return ["held": midi]
        case "chimera_note_off":
            let midi = try requiredInt(arguments, key: "midi")
            model.noteOff(midi)
            return ["released": midi]
        case "chimera_speak":
            model.mode = .speak
            let generate = arguments["generate"] as? Bool ?? false
            if generate {
                try await model.generateText(for: .speak, model: arguments["ollamaModel"] as? String, prompt: arguments["prompt"] as? String)
            } else {
                model.speechText = try requiredString(arguments, key: "text")
                model.speechUsesIPA = arguments["ipa"] as? Bool ?? false
            }
            model.speechRate = boundedNumber(arguments, key: "rate", default: 1, range: 0.5...1.8)
            if let f0 = optionalNumber(arguments, key: "f0") { model.source.f0 = min(1_100, max(40, f0)) }
            if model.isRemoteController {
                var result = try await model.remoteSpeak()
                result["generated"] = generate
                result["text"] = model.speechText
                return result
            }
            var result = try await model.speakNow(text: model.speechText, ipa: model.speechUsesIPA)
            result["generated"] = generate
            return result
        case "chimera_stop_speech":
            model.stopSpeech()
            return ["stopped": true]
        case "chimera_stop_singing":
            model.stopSinging()
            return ["stopped": true, "playingSong": NSNull(), "playhead": 0]
        case "chimera_sing":
            model.mode = .sing
            let action = arguments["action"] as? String ?? "play"
            guard ["play", "set", "generate", "stop", "note-on", "note-off"].contains(action) else {
                throw ChimeraError(message: "Unknown sing action: \(action)")
            }
            if action == "stop" {
                model.stopSinging()
                return ["stopped": true, "playhead": 0]
            }
            if action == "note-on" {
                model.vibrato = boundedNumber(arguments, key: "vibrato", default: model.vibrato, range: 0...100)
                let midi = int(arguments, key: "midi", default: 60, range: 0...127)
                if model.isRemoteController {
                    model.noteOn(midi)
                    return ["sung": midi, "syllable": model.songSyllable ?? NSNull()]
                }
                guard let value = arguments["syllable"] as? [String: Any] else {
                    throw ChimeraError(message: "note-on requires a validated syllable")
                }
                let data = try JSONSerialization.data(withJSONObject: value)
                let syllable = try JSONDecoder().decode(Syllable.self, from: data)
                model.singSyllableOn(syllable, midi: midi)
                return ["sung": midi, "syllable": syllable.text]
            }
            if action == "note-off" {
                let midi = int(arguments, key: "midi", default: 60, range: 0...127)
                model.noteOff(midi)
                return ["released": midi]
            }
            let generate = (arguments["generate"] as? Bool ?? false) || action == "generate"
            if generate {
                try await model.generateText(for: .sing, model: arguments["ollamaModel"] as? String, prompt: arguments["prompt"] as? String)
                try model.applyLyricsToSong(model.lyrics)
            } else if let lyrics = arguments["lyrics"] as? String {
                if model.isRemoteController || !model.songNotes.isEmpty {
                    try model.applyLyricsToSong(lyrics)
                } else {
                    model.lyrics = lyrics
                    model.rebuildSyllables()
                }
            }
            model.vibrato = boundedNumber(arguments, key: "vibrato", default: model.vibrato, range: 0...100)
            model.songBPM = boundedNumber(arguments, key: "bpm", default: model.songBPM, range: 40...240)
            if let values = arguments["notes"] as? [Any] {
                guard values.count <= 256 else { throw ChimeraError(message: "A score can contain at most 256 notes.") }
                let data = try JSONSerialization.data(withJSONObject: values)
                model.songNotes = try JSONDecoder().decode([SingNote].self, from: data)
            }
            if action == "set" || action == "generate" {
                var result = status()
                result["generated"] = generate
                result["lyrics"] = model.lyrics
                return result
            }
            if let value = arguments["song"] as? [String: Any] {
                let data = try JSONSerialization.data(withJSONObject: value)
                let song = try JSONDecoder().decode(DemoSong.self, from: data)
                var result = try await model.singPresetNow(song)
                result["generated"] = generate
                result["lyrics"] = model.lyrics
                return result
            }
            if model.isRemoteController || arguments["notes"] != nil {
                var result = try await model.singNow(
                    notes: model.songNotes,
                    title: arguments["title"] as? String ?? "Current score",
                    bpm: model.songBPM
                )
                result["generated"] = generate
                result["lyrics"] = model.lyrics
                return result
            }
            let midi = int(arguments, key: "midi", default: 60, range: 0...127)
            let duration = boundedNumber(arguments, key: "duration", default: 1, range: 0.05...30)
            model.noteOn(midi)
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            model.noteOff(midi)
            return ["sung": midi, "duration": duration, "generated": generate, "lyrics": model.lyrics]
        case "chimera_beatbox":
            let action = try requiredString(arguments, key: "action")
            model.mode = .beatbox
            if let bpm = optionalNumber(arguments, key: "bpm") { model.beatBPM = min(180, max(50, bpm)) }
            if let swing = optionalNumber(arguments, key: "swing") { model.beatSwing = min(0.7, max(0, swing)) }
            switch action {
            case "play": model.setBeatPlaying(true)
            case "stop": model.setBeatPlaying(false)
            case "hit": model.beatHit(try requiredString(arguments, key: "sound"))
            case "set":
                if arguments["steps"] != nil { model.replaceBeatSteps(try beatSteps(arguments)) }
            default: throw ChimeraError(message: "Unknown beatbox action: \(action)")
            }
            return [
                "action": action,
                "playing": model.beatPlaying,
                "bpm": model.beatBPM,
                "swing": model.beatSwing,
                "steps": try jsonValue(model.beatSteps),
                "beatStep": model.beatPlayhead
            ]
        case "chimera_creature":
            model.mode = .bestiary
            let id = arguments["id"] as? String ?? model.selectedCreatureID
            model.selectCreature(id)
            if let params = arguments["params"] as? [String: Any] {
                for (key, value) in params {
                    if let number = value as? NSNumber { model.setCreatureParam(key, value: number.doubleValue) }
                }
            }
            if let call = arguments["call"] as? String { model.playCall(call) }
            return ["creature": model.selectedCreatureID, "call": arguments["call"] ?? NSNull()]
        case "chimera_set_voice":
            if let modeName = arguments["mode"] as? String {
                guard let mode = InstrumentMode(rawValue: modeName.uppercased()) else {
                    throw ChimeraError(message: "Unknown mode: \(modeName)")
                }
                model.mode = mode
            }
            if let body = arguments["body"] as? String {
                switch body {
                case "male": model.setBody(.male)
                case "female": model.setBody(.female)
                case "child": model.setBody(.child)
                default: throw ChimeraError(message: "Unknown body: \(body)")
                }
            }
            if let body = arguments["bodyMix"] as? [String: Any] {
                guard let female = (body["female"] as? NSNumber)?.doubleValue,
                      let child = (body["child"] as? NSNumber)?.doubleValue else {
                    throw ChimeraError(message: "bodyMix requires numeric female and child weights")
                }
                model.setBody(BodyMix(female: min(1, max(0, female)), child: min(1, max(0, child))))
            }
            if let source = arguments["source"] as? [String: Any] { setSource(source) }
            if let whisper = arguments["whisper"] as? Bool { model.setWhisper(whisper) }
            if let artic = arguments["artic"] as? [String: Any] { setArtic(artic) }
            return status()
        case "chimera_set_gate":
            guard let on = arguments["on"] as? Bool else { throw ChimeraError(message: "on must be a boolean") }
            model.hold = on
            return ["gate": on]
        case "chimera_stop":
            model.stopAll()
            return ["stopped": true]
        default:
            throw ChimeraError(message: "Unknown tool: \(name)")
        }
    }

    private func status() -> [String: Any] {
        var result: [String: Any] = [
            "audioRunning": model.isStarted,
            "mode": model.mode.rawValue.lowercased(),
            "whisper": model.whisperEnabled,
            "voiced": model.source.voiced,
            "body": model.bodyMix.child > 0.5 ? "child" : model.bodyMix.female > 0.5 ? "female" : "male",
            "heldNotes": model.heldNotes,
            "speechText": model.speechText,
            "speechUsesIPA": model.speechUsesIPA,
            "speechRate": model.speechRate,
            "transcription": model.transcription,
            "speechSegments": (try? jsonValue(model.speechSegments)) ?? NSNull(),
            "speechGestures": (try? jsonValue(model.speechGestures)) ?? NSNull(),
            "beatSteps": (try? jsonValue(model.beatSteps)) ?? NSNull(),
            "beatText": model.beatText,
            "beatBPM": model.beatBPM,
            "beatSwing": model.beatSwing,
            "beatPlaying": model.beatPlaying,
            "beatStep": model.beatPlayhead,
            "lyrics": model.lyrics,
            "songNotes": (try? jsonValue(model.songNotes)) ?? NSNull(),
            "songBPM": model.songBPM,
            "vibrato": model.vibrato,
            "playingSong": model.playingSong ?? NSNull(),
            "songPlayhead": model.songPlayhead,
            "songNoteIndex": model.songNoteIndex,
            "songSyllable": model.songSyllable ?? NSNull(),
            "speechPlanEnd": model.speechPlanEnd,
            "speechPlanOffset": model.speechPlanOffset,
            "engineRunning": model.audioEngineRunning,
            "renderedFrames": model.audioRenderedFrames,
            "headConnected": model.headConnected,
            "mcp": "http://127.0.0.1:\(port)/mcp",
            "headStream": model.headStreamURL ?? NSNull(),
            "headClients": model.headStreamClientCount,
            "ollama": [
                "available": !model.ollamaModels.isEmpty,
                "models": model.ollamaModels,
                "selectedModel": model.selectedOllamaModel,
                "busy": model.ollamaBusy
            ]
        ]
        if model.mode == .bestiary {
            result["creature"] = model.selectedCreatureID
            result["gate"] = model.creatureTelemetry.gate
            result["outRms"] = model.creatureTelemetry.outRMS
            result["clock"] = model.creatureTelemetry.clock
        } else {
            result["f0"] = model.telemetry.f0
            result["gate"] = model.telemetry.gate
            result["outRms"] = model.telemetry.outRMS
            result["lungPressure"] = model.telemetry.lungPressure
            result["clock"] = model.telemetry.clock
        }
        return result
    }

    private func setSource(_ values: [String: Any]) {
        let paths: [String: WritableKeyPath<VoiceSource, Double>] = [
            "f0": \.f0, "glide": \.glide, "pressure": \.pressure,
            "breathiness": \.breathiness, "tension": \.tension, "fry": \.fry,
            "roughness": \.roughness, "vibratoDepth": \.vibratoDepth,
            "vibratoRate": \.vibratoRate, "drift": \.drift, "brightness": \.brightness
        ]
        for (key, value) in values {
            if key == "voiced", let voiced = value as? Bool { model.source.voiced = voiced }
            if let path = paths[key], let number = value as? NSNumber { model.source[keyPath: path] = number.doubleValue }
        }
    }

    private func setArtic(_ values: [String: Any]) {
        let paths: [String: WritableKeyPath<HumanArtic, Double>] = [
            "jaw": \.jaw, "tbX": \.tbX, "tbY": \.tbY, "ttX": \.ttX, "ttY": \.ttY,
            "ttCurl": \.ttCurl, "root": \.root, "lipAp": \.lipAp, "lipProt": \.lipProt,
            "lipWidth": \.lipWidth, "labiodental": \.labiodental, "velum": \.velum,
            "larynx": \.larynx, "epilarynx": \.epilarynx, "ventricular": \.ventricular,
            "lateral": \.lateral, "dorsum": \.dorsum
        ]
        for (key, value) in values {
            if let path = paths[key], let number = value as? NSNumber { model.artic[keyPath: path] = number.doubleValue }
        }
    }

    private func success(_ value: [String: Any]) -> [String: Any] {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": value
        ]
    }

    private func beatSteps(_ arguments: [String: Any]) throws -> [BeatStep?] {
        guard let values = arguments["steps"] as? [Any], values.count <= 128 else {
            throw ChimeraError(message: "steps must be an array containing at most 128 items")
        }
        let data = try JSONSerialization.data(withJSONObject: values)
        return try JSONDecoder().decode([BeatStep?].self, from: data)
    }

    private func jsonValue<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func requiredString(_ arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ChimeraError(message: "\(key) must be a non-empty string")
        }
        return value
    }

    private func requiredInt(_ arguments: [String: Any], key: String) throws -> Int {
        guard let value = arguments[key] as? NSNumber else {
            throw ChimeraError(message: "\(key) must be an integer")
        }
        return min(127, max(0, value.intValue))
    }

    private func optionalNumber(_ arguments: [String: Any], key: String) -> Double? {
        (arguments[key] as? NSNumber)?.doubleValue
    }

    private func boundedNumber(_ arguments: [String: Any], key: String, default defaultValue: Double, range: ClosedRange<Double>) -> Double {
        guard let value = optionalNumber(arguments, key: key) else { return defaultValue }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private func int(_ arguments: [String: Any], key: String, default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        guard let value = arguments[key] as? NSNumber else { return defaultValue }
        return min(range.upperBound, max(range.lowerBound, value.intValue))
    }
}

private func tool(name: String, description: String, properties: [String: Any], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties,
        "additionalProperties": false
    ]
    if !required.isEmpty { schema["required"] = required }
    return [
        "name": name,
        "description": description,
        "inputSchema": schema
    ]
}

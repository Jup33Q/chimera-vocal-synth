import Foundation

private struct APIError: Decodable {
    let error: String
}

final class ChimeraAPI {
    func call<T: Decodable>(_ name: String, args: [String: Any] = [:]) throws -> T {
        var request = args
        request["fn"] = name
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let input = chimera_alloc(data.count) else {
            throw ChimeraError(message: "The engine could not allocate a request buffer.")
        }
        defer { chimera_free(input, data.count) }
        data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(input, base, data.count)
            }
        }
        let status = chimera_call(input, data.count)
        let length = chimera_result_len()
        let result = Data(bytes: chimera_result_ptr(), count: length)
        if status != 0 {
            let apiError = try? JSONDecoder().decode(APIError.self, from: result)
            throw ChimeraError(message: apiError?.error ?? "Engine call failed: \(name)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: result)
        } catch {
            throw ChimeraError(message: "Could not decode \(name): \(error.localizedDescription)")
        }
    }

    func catalog() throws -> VoiceCatalog {
        try call("catalog")
    }

    func restTip(_ artic: HumanArtic) throws -> Vec2 {
        try call("restTip", args: ["jaw": artic.jaw, "tbX": artic.tbX, "tbY": artic.tbY])
    }

    func loadDictionary() throws {
        guard let url = Bundle.main.url(forResource: "cmudict", withExtension: "txt") else {
            throw ChimeraError(message: "CMUdict is missing from the application bundle.")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let loaded: Bool = try call("g2pLoad", args: ["text": text])
        if !loaded {
            throw ChimeraError(message: "CMUdict could not be loaded.")
        }
    }

    func phrases(for text: String, ipa: Bool) throws -> [Phrase] {
        if ipa {
            let segments: [Segment] = try call("tokenizeIpa", args: ["text": text])
            return [Phrase(segments: segments, intonation: "statement", pause: 0.3, words: [])]
        }
        return try call("g2pPhrases", args: ["text": text])
    }

    func planSpeech(_ phrases: [Phrase], body: BodyMix, rate: Double, f0: Double) throws -> Plan {
        let phraseValues = try phrases.map { try jsonObject($0) }
        return try call("planPhrases", args: [
            "phrases": phraseValues,
            "options": ["body": try jsonObject(body), "t0": 0, "rate": rate, "f0": f0]
        ])
    }

    func syllables(for lyrics: String) throws -> [Syllable] {
        try call("lyricsToSyllables", args: ["text": lyrics])
    }

    func planNoteOn(_ syllable: Syllable, midi: Int, body: BodyMix, vibrato: Double, tag: Double) throws -> [Gesture] {
        try call("planNoteOn", args: [
            "syl": try jsonObject(syllable),
            "midi": midi,
            "options": ["body": try jsonObject(body), "vibrato": vibrato, "tag": tag]
        ])
    }

    func planNoteOff(_ syllable: Syllable, midi: Int, body: BodyMix) throws -> [Gesture] {
        try call("planNoteOff", args: [
            "syl": try jsonObject(syllable),
            "midi": midi,
            "body": try jsonObject(body)
        ])
    }

    func planSong(_ song: DemoSong, body: BodyMix, vibrato: Double) throws -> Plan {
        let syllables = try syllables(for: song.lyrics)
        let bodyName = body.child > 0.5 ? "child" : body.female > 0.5 ? "female" : "male"
        let shift = (song.octave[bodyName] ?? 0) * 12
        let notes = try song.notes.enumerated().map { index, note -> [String: Any] in
            [
                "midi": note[0] + shift,
                "beats": note[1],
                "syl": try jsonObject(syllables[index % syllables.count])
            ]
        }
        return try call("planSong", args: [
            "notes": notes,
            "options": ["body": try jsonObject(body), "bpm": song.bpm, "t0": 0.35, "vibrato": vibrato]
        ])
    }

    func planSong(_ score: [SingNote], body: BodyMix, bpm: Double, vibrato: Double) throws -> Plan {
        let notes = score.sorted { $0.start < $1.start }
        guard !notes.isEmpty else { throw ChimeraError(message: "Add at least one note before playing.") }
        guard bpm >= 40, bpm <= 240 else { throw ChimeraError(message: "Tempo must be between 40 and 240 BPM.") }
        let secondsPerBeat = 60 / bpm
        var gestures: [Gesture] = []
        var segments: [PlannedSegment] = []
        var end = 0.0
        var index = 0
        while index < notes.count {
            var last = index
            var runEnd = notes[index].start + notes[index].duration
            while last + 1 < notes.count {
                let next = notes[last + 1]
                guard next.start >= runEnd - 0.0001 else {
                    throw ChimeraError(message: "Notes \(last + 1) and \(last + 2) overlap. Sing supports one melodic line.")
                }
                if next.start > runEnd + 0.0001 { break }
                last += 1
                runEnd = next.start + next.duration
            }
            let run = Array(notes[index...last])
            let sung = try run.enumerated().map { offset, note -> [String: Any] in
                guard note.midi >= 0, note.midi <= 127 else {
                    throw ChimeraError(message: "Note \(index + offset + 1) has an invalid MIDI pitch.")
                }
                guard note.start >= 0, note.duration >= 0.05, note.duration <= 32 else {
                    throw ChimeraError(message: "Note \(index + offset + 1) needs a positive start and a duration from 0.05 to 32 beats.")
                }
                let text = note.lyric.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw ChimeraError(message: "Note \(index + offset + 1) is missing a lyric syllable.")
                }
                let syllable: Syllable
                if let supplied = note.syllable, supplied.text == text {
                    syllable = supplied
                } else {
                    let parsed = try syllables(for: text)
                    guard parsed.count == 1 else {
                        throw ChimeraError(message: "Note \(index + offset + 1) needs exactly one lyric syllable; use - or ~ for a melisma.")
                    }
                    syllable = parsed[0]
                }
                return [
                    "midi": note.midi,
                    "beats": note.duration,
                    "syl": try jsonObject(syllable)
                ]
            }
            let plan: Plan = try call("planSong", args: [
                "notes": sung,
                "options": [
                    "body": try jsonObject(body),
                    "bpm": bpm,
                    "t0": 0.35 + run[0].start * secondsPerBeat,
                    "vibrato": vibrato
                ]
            ])
            gestures.append(contentsOf: plan.gestures)
            segments.append(contentsOf: plan.segments)
            end = max(end, plan.end, (notes[last].start + notes[last].duration) * secondsPerBeat + 0.35)
            index = last + 1
        }
        guard gestures.count <= 4_000 else {
            throw ChimeraError(message: "This score produces more than 4,000 gestures. Shorten it before playing.")
        }
        return Plan(gestures: gestures, segments: segments, end: end)
    }

    func parseBeat(_ text: String) throws -> [BeatStep?] {
        try call("parseBeat", args: ["text": text])
    }

    func formatBeat(_ steps: [BeatStep?]) throws -> String {
        try call("formatBeat", args: ["steps": try jsonObject(steps)])
    }

    func beatReady(_ body: BodyMix) throws -> [String: Double] {
        try call("beatReady", args: ["body": try jsonObject(body)])
    }

    func airwayModel(body: BodyMix, sampleRate: Double) throws -> AirwayModel {
        try call("model", args: ["body": try jsonObject(body), "sampleRate": sampleRate])
    }

    func frame(model: Int, artic: HumanArtic) throws -> HumanFrame {
        try call("frame", args: ["model": model, "artic": try jsonObject(artic)])
    }

    func transfer(model: Int, artic: HumanArtic) throws -> Transfer {
        try call("transfer", args: ["model": model, "artic": try jsonObject(artic)])
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}

import Foundation
import SwiftUI

enum InstrumentMode: String, CaseIterable, Identifiable {
    case play = "PLAY"
    case speak = "SPEAK"
    case sing = "SING"
    case beatbox = "BEATBOX"
    case bestiary = "BESTIARY"

    var id: String { rawValue }
}

@MainActor
final class InstrumentModel: ObservableObject {
    @Published private(set) var catalog: VoiceCatalog?
    @Published private(set) var isReady = false
    @Published private(set) var isStarted = false
    @Published var lastError: String?

    @Published var mode: InstrumentMode = .play {
        didSet { modeChanged(from: oldValue) }
    }
    @Published var bodyMix = BodyMix.male
    @Published private(set) var whisperEnabled = false
    @Published var source = VoiceSource.placeholder {
        didSet {
            if whisperEnabled && source.voiced {
                source.voiced = false
                return
            }
            audio?.setSource(source)
            if !applyingRemoteWhisper { remote?.setSource(source) }
        }
    }
    @Published var artic = HumanArtic.zero {
        didSet {
            audio?.setArtic(artic, tipFree: true)
            remote?.setArtic(artic)
        }
    }
    @Published var volume = 0.8 {
        didSet { audio?.setVolume(volume) }
    }
    @Published var hold = false {
        didSet { updateGate() }
    }
    @Published private(set) var heldNotes: [Int] = []
    @Published private(set) var telemetry = VoiceTelemetry()
    @Published private(set) var creatureTelemetry = CreatureTelemetry()
    @Published private(set) var frame: HumanFrame?
    @Published private(set) var transfer: Transfer?
    @Published private(set) var vowelSpace: VowelSpace?

    @Published var speechText = "The voice is made of air."
    @Published var speechUsesIPA = false
    @Published var speechRate = 1.0
    @Published private(set) var transcription = ""
    @Published private(set) var speechSegments: [PlannedSegment] = []
    @Published private(set) var speechGestures: [Gesture] = []
    @Published private(set) var speechPlanEnd = 0.0
    @Published private(set) var speechPlanOffset = 0.0

    @Published var lyrics = "Hello there, I am a voice made of air."
    @Published var vibrato = 35.0
    @Published var songBPM = 100.0 {
        didSet {
            if isReady, oldValue != songBPM, playingSong != nil { stopSinging() }
        }
    }
    @Published var songNotes: [SingNote] = [] {
        didSet {
            if isReady, oldValue != songNotes, playingSong != nil { stopSinging() }
        }
    }
    @Published private(set) var songSyllables: [Syllable] = []
    @Published private(set) var playingSong: String?
    @Published private(set) var songPlayhead = 0.0
    @Published private(set) var songNoteIndex = -1
    @Published private(set) var songSyllable: String?
    @Published private(set) var syllableCursor = 0

    @Published private(set) var beatSteps: [BeatStep?] = []
    @Published private(set) var beatText = ""
    @Published var beatBPM = 96.0 {
        didSet {
            audio?.setBeat(bpm: beatBPM)
            if isReady { remote?.setBeat(bpm: beatBPM, swing: beatSwing) }
        }
    }
    @Published var beatSwing = 0.0 {
        didSet {
            audio?.setBeat(swing: beatSwing)
            if isReady { remote?.setBeat(bpm: beatBPM, swing: beatSwing) }
        }
    }
    @Published private(set) var beatPlaying = false
    @Published private(set) var beatPlayhead = -1
    @Published var selectedBeatSound = ""

    @Published private(set) var selectedCreatureID = "songbird"
    @Published private(set) var creatureInfo: CreatureInfo?
    @Published private(set) var creatureParams: [String: [String: Double]] = [:]

    @Published private(set) var ollamaModels: [String] = []
    @Published var selectedOllamaModel = ""
    @Published var ollamaPrompt = "A curious robot discovering the expressive power of the human voice"
    @Published private(set) var ollamaBusy = false
    @Published private(set) var ollamaStatus = "Checking local models"

    let instanceID = UUID().uuidString
    let projectID: String
    let projectName: String
    let mcpPort: Int
    let sourceName: String

    @Published private(set) var headConnected = false
    @Published private(set) var headEngineRunning = false
    @Published private(set) var headRenderedFrames = 0

    var isRemoteController: Bool { remote != nil }
    var audioEngineRunning: Bool { audio?.engineIsRunning ?? headEngineRunning }
    var audioRenderedFrames: Int { audio?.renderedFrames ?? headRenderedFrames }
    var headStreamClientCount: Int { headStream.clientCount }
    var headStreamURL: String? { servesHeadStream ? "http://127.0.0.1:\(mcpPort)/head/stream" : nil }
    var headStreamService: HeadStreamService? { servesHeadStream ? headStream : nil }

    private let api = ChimeraAPI()
    private let ollama = OllamaClient()
    private let audio: AudioController?
    private let remote: RemoteHeadClient?
    private let mcpServerName: String
    private let mcpTools: [String]?
    private let servesHeadStream: Bool
    private let startsMCP: Bool
    private let headStream = HeadStreamService()
    private var airway: AirwayModel?
    private var timer: Timer?
    private var mcpServer: MCPServer?
    private var tickCount = 0
    private var remoteTickCount = 0
    private var sounding: (syllable: Syllable, midi: Int, tag: Double)?
    private var nextTag = 2.0
    private var scheduledSongNotes: [SingNote] = []
    private var scheduledSongBPM = 100.0
    private var songRequestSerial = 0
    private var voicedBeforeWhisper = true
    private var applyingRemoteWhisper = false
    private var pendingBodyModel: BodyMix?
    private var bodyModelTask: Task<Void, Never>?

    init(
        mcpPort: Int = 8642,
        mcpServerName: String = "chimera-mac",
        mcpTools: [String]? = nil,
        servesHeadStream: Bool = false,
        projectID: String = "chimera-mac",
        projectName: String = "Chimera",
        sourceName: String = "play",
        controlledByHead: Bool = false,
        startsMCP: Bool = true,
        initialMode: InstrumentMode = .play
    ) {
        self.mcpPort = mcpPort
        self.mcpServerName = mcpServerName
        self.mcpTools = mcpTools
        self.servesHeadStream = servesHeadStream
        self.projectID = projectID
        self.projectName = projectName
        self.sourceName = sourceName
        self.startsMCP = startsMCP
        self.mode = initialMode
        if controlledByHead {
            audio = nil
        } else {
            do {
                audio = try AudioController()
            } catch {
                audio = nil
                lastError = error.localizedDescription
            }
        }
        if controlledByHead {
            let client = RemoteHeadClient()
            remote = client
            client.onFrame = { [weak self] in self?.applyRemoteFrame($0) }
            client.onConnection = { [weak self] connected in
                self?.headConnected = connected
                if !connected { self?.isStarted = false }
                if connected, self?.mode == .sing {
                    Task { [weak self] in await self?.recoverRemoteSong() }
                }
            }
            client.onError = { [weak self] in self?.lastError = $0 }
        } else {
            remote = nil
        }
    }

    func prepare() {
        guard !isReady else { return }
        remote?.start()
        do {
            let catalog = try api.catalog()
            self.catalog = catalog
            source = catalog.defaultSource
            let tip = try api.restTip(catalog.neutral)
            artic = catalog.neutral
            artic.ttX = tip.x
            artic.ttY = tip.y
            airway = try api.airwayModel(body: bodyMix, sampleRate: audio?.sampleRate ?? 48_000)
            vowelSpace = VowelSpace(catalog: catalog, body: bodyMix)
            for creature in catalog.creatures {
                creatureParams[creature.id] = Dictionary(uniqueKeysWithValues: creature.params.map { ($0.key, $0.defaultValue) })
            }
            if let preset = catalog.beatPresets.first {
                beatSteps = try api.parseBeat(preset.text)
                beatText = preset.text
                beatBPM = preset.bpm
                beatSwing = preset.swing
            }
            selectedBeatSound = catalog.beatSounds.first?.id ?? ""
            try api.loadDictionary()
            songSyllables = (try? api.syllables(for: lyrics)) ?? []
            if mode == .sing, songNotes.isEmpty {
                songNotes = defaultSongNotes(syllables: songSyllables)
            }
            refreshGeometry()
            isReady = true
            if startsMCP, mcpServer == nil {
                let router = MCPToolRouter(model: self, port: mcpPort, allowedTools: mcpTools)
                let server = MCPServer(
                    port: mcpPort,
                    serverName: mcpServerName,
                    router: router,
                    headStream: servesHeadStream ? headStream : nil
                )
                server.start()
                mcpServer = server
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startAudio() {
        prepare()
        if let remote {
            Task {
                do {
                    try await remote.startAudio()
                    isStarted = true
                } catch {
                    lastError = error.localizedDescription
                }
            }
            return
        }
        guard !isStarted, let audio else { return }
        do {
            try audio.start()
            audio.setVolume(volume)
            audio.setSource(source)
            audio.setArtic(artic, tipFree: true)
            if mode == .bestiary { try setupCreature() }
            isStarted = true
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setBody(_ body: BodyMix) {
        guard body != bodyMix else { return }
        bodyMix = body
        remote?.setBody(body)
        source.f0 = body.child > 0.5 ? 260 : body.female > 0.5 ? 196 : 110
        scheduleBodyModel(body)
    }

    func setWhisper(_ enabled: Bool) {
        if let remote {
            remote.setWhisper(enabled)
            return
        }
        guard enabled != whisperEnabled else {
            if enabled && source.voiced { source.voiced = false }
            return
        }
        if enabled {
            voicedBeforeWhisper = source.voiced
            whisperEnabled = true
            source.voiced = false
        } else {
            whisperEnabled = false
            source.voiced = voicedBeforeWhisper
        }
    }

    private func scheduleBodyModel(_ body: BodyMix) {
        pendingBodyModel = body
        guard bodyModelTask == nil else { return }
        bodyModelTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            let body = self.pendingBodyModel
            self.pendingBodyModel = nil
            self.bodyModelTask = nil
            if let body { self.applyBodyModel(body) }
        }
    }

    private func applyBodyModel(_ body: BodyMix) {
        audio?.setBody(body)
        if let catalog { vowelSpace = VowelSpace(catalog: catalog, body: body) }
        do {
            airway = try api.airwayModel(body: body, sampleRate: audio?.sampleRate ?? 48_000)
            refreshGeometry()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setVowelPosition(x: Double, y: Double) {
        guard let vowelSpace else { return }
        artic = vowelSpace.articulation(x: x, y: y, base: catalog?.neutral ?? .zero)
        refreshGeometry()
    }

    func remotePlayNote(midi: Int, duration: Double) async throws -> [String: Any] {
        guard let remote else { throw ChimeraError(message: "This application owns its audio engine.") }
        return try await remote.playNote(midi: midi, duration: duration)
    }

    func speak() {
        Task {
            do {
                _ = try await speakNow(text: speechText, ipa: speechUsesIPA)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func speakNow(text: String, ipa: Bool) async throws -> [String: Any] {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ChimeraError(message: "No text was sent to Head because the utterance is empty.") }
        speechText = input
        speechUsesIPA = ipa
        if remote != nil {
            return try await remoteSpeak(text: input, ipa: ipa)
        }
        startAudio()
        let phrases = try api.phrases(for: input, ipa: ipa)
        guard !phrases.isEmpty, !phrases.allSatisfy({ $0.segments.isEmpty }) else {
            throw ChimeraError(message: "The input produced no speakable segments.")
        }
        let plan = try api.planSpeech(phrases, body: bodyMix, rate: speechRate, f0: source.f0)
        speechPlanOffset = audio?.schedule(plan.gestures, controlKeys: controlKeys) ?? 0
        speechGestures = plan.gestures
        speechPlanEnd = plan.end
        speechSegments = plan.segments
        transcription = phrases.map { phrase in
            phrase.segments.map { segment in
                (segment.stress == 1 ? "ˈ" : segment.stress == 2 ? "ˌ" : "") + segment.ipa + (segment.wordEnd == true ? " " : "")
            }.joined()
        }.joined(separator: " | ")
        return [
            "text": input,
            "transcription": transcription,
            "segmentData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(speechSegments)),
            "gestureData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(speechGestures)),
            "planEnd": speechPlanEnd,
            "planOffset": speechPlanOffset
        ]
    }

    func remoteSpeak(text: String? = nil, ipa: Bool? = nil) async throws -> [String: Any] {
        guard let remote else { throw ChimeraError(message: "This application owns its audio engine.") }
        let result = try await remote.speak(text: text ?? speechText, ipa: ipa ?? speechUsesIPA, rate: speechRate, f0: source.f0)
        if let text = result["transcription"] as? String { transcription = text }
        if let values = result["segmentData"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: values),
           let segments = try? JSONDecoder().decode([PlannedSegment].self, from: data) {
            speechSegments = segments
        }
        if let values = result["gestureData"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: values),
           let gestures = try? JSONDecoder().decode([Gesture].self, from: data) {
            speechGestures = gestures
        }
        if let end = (result["planEnd"] as? NSNumber)?.doubleValue { speechPlanEnd = end }
        if let offset = (result["planOffset"] as? NSNumber)?.doubleValue { speechPlanOffset = offset }
        return result
    }

    func speakConsonant(_ consonant: String, vowel: String) {
        let utterance = "ˈ\(vowel)\(consonant)\(vowel)"
        stopSpeech()
        Task {
            do {
                _ = try await speakNow(text: utterance, ipa: true)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func stopSpeech() {
        audio?.stopSpeech()
        remote?.stopSpeech()
        speechSegments = []
    }

    func clearSpeech() {
        stopSpeech()
        transcription = ""
        speechGestures = []
        speechPlanEnd = 0
        speechPlanOffset = 0
    }

    func rebuildSyllables() {
        do {
            songSyllables = try api.syllables(for: lyrics)
            syllableCursor = 0
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyLyricsToSong(_ text: String) throws {
        let parsed = try api.syllables(for: text)
        guard !parsed.isEmpty else {
            throw ChimeraError(message: "No singable English syllables were found. No notes were changed.")
        }
        if playingSong != nil { stopSinging() }
        lyrics = text
        songSyllables = parsed
        syllableCursor = 0
        var notes = songNotes.sorted { $0.start < $1.start }
        if notes.isEmpty { notes = defaultSongNotes(syllables: parsed) }
        for index in notes.indices {
            notes[index].lyric = index < parsed.count ? parsed[index].text : ""
            notes[index].syllable = index < parsed.count ? parsed[index] : nil
        }
        if parsed.count > notes.count {
            let oldCount = notes.count
            let lastEnd = notes.map { $0.start + $0.duration }.max() ?? 0
            let pitch = notes.last?.midi ?? 60
            for index in oldCount..<parsed.count {
                notes.append(SingNote(midi: pitch, start: lastEnd + Double(index - oldCount), duration: 1, lyric: parsed[index].text, syllable: parsed[index]))
            }
        }
        songNotes = notes
    }

    func addSongNote() {
        let end = songNotes.map { $0.start + $0.duration }.max() ?? 0
        let pitch = songNotes.last?.midi ?? 60
        songNotes.append(SingNote(midi: pitch, start: end, duration: 1, lyric: ""))
    }

    func updateSongNote(_ note: SingNote) {
        guard let index = songNotes.firstIndex(where: { $0.id == note.id }) else { return }
        var edited = note
        if edited.lyric != songNotes[index].lyric { edited.syllable = nil }
        songNotes[index] = edited
        songNotes.sort { $0.start < $1.start }
    }

    func deleteSongNote(_ id: UUID) {
        songNotes.removeAll { $0.id == id }
    }

    func clearSong() {
        stopSinging()
        songNotes = []
        lyrics = ""
        songSyllables = []
        syllableCursor = 0
        speechSegments = []
        speechGestures = []
        speechPlanEnd = 0
        speechPlanOffset = 0
        scheduledSongNotes = []
    }

    func playCurrentSong() {
        Task {
            do {
                _ = try await singNow(notes: songNotes, title: "Current score", bpm: songBPM)
            } catch is CancellationError {
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func playSong(_ song: DemoSong) {
        Task {
            do {
                _ = try await singPresetNow(song)
            } catch is CancellationError {
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func singNow(notes: [SingNote], title: String, bpm: Double) async throws -> [String: Any] {
        stopSinging()
        let request = songRequestSerial
        if let remote {
            let result = try await remote.sing(notes: notes, bpm: bpm, vibrato: vibrato, title: title)
            guard request == songRequestSerial else { throw CancellationError() }
            try applyRemoteSongResult(result, fallbackTitle: title, fallbackBPM: bpm)
            return result
        }
        let plan = try api.planSong(notes, body: bodyMix, bpm: bpm, vibrato: vibrato)
        return try scheduleSongPlan(plan, notes: notes, title: title, bpm: bpm)
    }

    func singPresetNow(_ song: DemoSong) async throws -> [String: Any] {
        stopSinging()
        loadSongEditor(song)
        let request = songRequestSerial
        if let remote {
            let result = try await remote.sing(song: song, vibrato: vibrato)
            guard request == songRequestSerial else { throw CancellationError() }
            try applyRemoteSongResult(result, fallbackTitle: song.name, fallbackBPM: song.bpm)
            return result
        }
        let plan = try api.planSong(song, body: bodyMix, vibrato: vibrato)
        return try scheduleSongPlan(plan, notes: songNotes, title: song.name, bpm: song.bpm)
    }

    private func scheduleSongPlan(_ plan: Plan, notes: [SingNote], title: String, bpm: Double) throws -> [String: Any] {
        startAudio()
        guard let audio else { throw ChimeraError(message: "Head does not have an available audio engine.") }
        speechPlanOffset = audio.schedule(plan.gestures, controlKeys: controlKeys)
        speechPlanEnd = plan.end
        speechSegments = plan.segments
        speechGestures = plan.gestures
        scheduledSongNotes = notes.sorted { $0.start < $1.start }
        scheduledSongBPM = bpm
        songPlayhead = 0
        songNoteIndex = -1
        songSyllable = nil
        playingSong = title
        return try songResult()
    }

    private func recoverRemoteSong() async {
        guard let remote else { return }
        let request = songRequestSerial
        do {
            let status = try await remote.currentStatus()
            guard request == songRequestSerial, mode == .sing, status["playingSong"] as? String != nil else { return }
            var result = status
            result["segmentData"] = status["speechSegments"]
            result["gestureData"] = status["speechGestures"]
            result["bpm"] = status["songBPM"]
            result["planEnd"] = status["speechPlanEnd"]
            result["planOffset"] = status["speechPlanOffset"]
            try applyRemoteSongResult(result, fallbackTitle: "Head song", fallbackBPM: songBPM)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyRemoteSongResult(_ result: [String: Any], fallbackTitle: String, fallbackBPM: Double) throws {
        if let values = result["segmentData"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: values)
            speechSegments = try JSONDecoder().decode([PlannedSegment].self, from: data)
        }
        if let values = result["gestureData"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: values)
            speechGestures = try JSONDecoder().decode([Gesture].self, from: data)
        }
        if let values = result["songNotes"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: values)
            let notes = try JSONDecoder().decode([SingNote].self, from: data)
            scheduledSongNotes = notes
            if songNotes != notes { songNotes = notes }
        }
        if let end = (result["planEnd"] as? NSNumber)?.doubleValue { speechPlanEnd = end }
        if let offset = (result["planOffset"] as? NSNumber)?.doubleValue { speechPlanOffset = offset }
        scheduledSongBPM = (result["bpm"] as? NSNumber)?.doubleValue ?? fallbackBPM
        songPlayhead = 0
        songNoteIndex = -1
        songSyllable = nil
        playingSong = result["playingSong"] as? String ?? fallbackTitle
    }

    private func songResult() throws -> [String: Any] {
        [
            "playingSong": playingSong ?? NSNull(),
            "songNotes": try JSONSerialization.jsonObject(with: JSONEncoder().encode(scheduledSongNotes)),
            "segmentData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(speechSegments)),
            "gestureData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(speechGestures)),
            "planEnd": speechPlanEnd,
            "planOffset": speechPlanOffset,
            "bpm": scheduledSongBPM,
            "playhead": songPlayhead,
            "noteIndex": songNoteIndex,
            "syllable": songSyllable ?? NSNull()
        ]
    }

    private func loadSongEditor(_ song: DemoSong) {
        lyrics = song.lyrics
        songBPM = song.bpm
        let parsed = (try? api.syllables(for: song.lyrics)) ?? []
        songSyllables = parsed
        let bodyName = bodyMix.child > 0.5 ? "child" : bodyMix.female > 0.5 ? "female" : "male"
        let shift = Int((song.octave[bodyName] ?? 0) * 12)
        var start = 0.0
        songNotes = song.notes.enumerated().map { index, note in
            let syllable = parsed.isEmpty ? nil : parsed[index % parsed.count]
            let result = SingNote(
                midi: Int(note[0]) + shift,
                start: start,
                duration: note[1],
                lyric: syllable?.text ?? "",
                syllable: syllable
            )
            start += note[1]
            return result
        }
    }

    private func defaultSongNotes(syllables: [Syllable]) -> [SingNote] {
        syllables.enumerated().map { index, syllable in
            SingNote(midi: 60, start: Double(index), duration: 1, lyric: syllable.text, syllable: syllable)
        }
    }

    func stopSinging() {
        songRequestSerial += 1
        audio?.stopSpeech()
        remote?.stopSinging()
        if let sounding {
            audio?.release(sounding.tag)
            audio?.release(sounding.tag + 1)
        }
        sounding = nil
        playingSong = nil
        songPlayhead = 0
        songNoteIndex = -1
        songSyllable = nil
    }

    func noteOn(_ midi: Int) {
        if let remote {
            if !heldNotes.contains(midi) { heldNotes.append(midi) }
            if mode == .sing {
                stopSinging()
                if songSyllables.isEmpty { rebuildSyllables() }
                guard !songSyllables.isEmpty else {
                    lastError = "No lyric syllables are available for MIDI input. Add lyrics first."
                    return
                }
                let syllable = songSyllables[syllableCursor % songSyllables.count]
                remote.singNoteOn(syllable, midi: midi, vibrato: vibrato)
                songSyllable = syllable.text
                syllableCursor = (syllableCursor + 1) % songSyllables.count
                return
            }
            if mode != .bestiary { source.f0 = 440 * pow(2, Double(midi - 69) / 12) }
            remote.noteOn(midi)
            updateGate()
            return
        }
        startAudio()
        if !heldNotes.contains(midi) { heldNotes.append(midi) }
        if mode == .sing {
            singNoteOn(midi)
            return
        }
        if mode == .bestiary {
            if let creature = catalog?.creatures.first(where: { $0.id == selectedCreatureID }),
               let pitch = creature.params.first(where: { $0.role == "pitch" }) {
                let frequency = creatureFrequency(midi: midi, param: pitch)
                setCreatureParam(pitch.key, value: frequency)
            }
        } else {
            source.f0 = 440 * pow(2, Double(midi - 69) / 12)
        }
        updateGate()
    }

    func noteOff(_ midi: Int) {
        heldNotes.removeAll { $0 == midi }
        if mode == .sing {
            if remote != nil { remote?.singNoteOff(midi) } else { singNoteOff(midi) }
            if heldNotes.isEmpty { songSyllable = nil }
            return
        }
        if let last = heldNotes.last {
            if mode == .bestiary {
                if let creature = catalog?.creatures.first(where: { $0.id == selectedCreatureID }),
                   let pitch = creature.params.first(where: { $0.role == "pitch" }) {
                    setCreatureParam(pitch.key, value: creatureFrequency(midi: last, param: pitch))
                }
            } else {
                source.f0 = 440 * pow(2, Double(last - 69) / 12)
            }
        }
        remote?.noteOff(midi)
        updateGate()
    }

    func toggleBeatStep(_ index: Int) {
        guard beatSteps.indices.contains(index), !selectedBeatSound.isEmpty else { return }
        var steps = beatSteps
        if steps[index]?.id == selectedBeatSound {
            steps[index] = nil
        } else {
            steps[index] = BeatStep(id: selectedBeatSound, note: selectedBeatSound == "m" ? catalog?.bassNote : nil, accent: nil)
        }
        replaceBeatSteps(steps)
    }

    func replaceBeatSteps(_ steps: [BeatStep?]) {
        beatSteps = steps
        beatText = (try? api.formatBeat(steps)) ?? beatText
        audio?.setBeat(steps: steps)
        remote?.setBeat(steps: steps)
    }

    func applyBeatText(_ text: String) {
        beatText = text
        do {
            let parsed = try api.parseBeat(text)
            guard !parsed.isEmpty else { return }
            let steps = Array(parsed.prefix(16)) + Array(repeating: nil, count: max(0, 16 - parsed.count))
            beatSteps = steps
            audio?.setBeat(steps: steps)
            remote?.setBeat(steps: steps)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadBeatPreset(_ preset: BeatPreset) {
        do {
            beatSteps = try api.parseBeat(preset.text)
            beatText = preset.text
            beatBPM = preset.bpm
            beatSwing = preset.swing
            audio?.setBeat(steps: beatSteps, bpm: beatBPM, swing: beatSwing)
            remote?.setBeat(steps: beatSteps, bpm: beatBPM, swing: beatSwing)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setBeatPlaying(_ playing: Bool) {
        if playing { startAudio() }
        beatPlaying = playing
        audio?.setBeat(steps: playing ? beatSteps : nil, bpm: playing ? beatBPM : nil, swing: playing ? beatSwing : nil, playing: playing)
        remote?.setBeat(playing: playing)
        if !playing { beatPlayhead = -1 }
    }

    func beatHit(_ id: String) {
        startAudio()
        audio?.beatHit(BeatStep(id: id, note: id == "m" ? catalog?.bassNote : nil, accent: nil))
        remote?.beatHit(id)
    }

    func selectCreature(_ id: String) {
        selectedCreatureID = id
        if mode == .bestiary {
            do { try setupCreature() } catch { lastError = error.localizedDescription }
        }
    }

    func setCreatureParam(_ key: String, value: Double) {
        creatureParams[selectedCreatureID]?[key] = value
        if let index = creatureInfo?.params.firstIndex(of: key) {
            audio?.setCreatureParam(index: index, value: value)
        }
    }

    func playCall(_ id: String) {
        startAudio()
        if let index = creatureInfo?.calls.firstIndex(of: id) {
            audio?.playCall(index: index)
        }
    }

    func refreshOllamaModels() async {
        do {
            let models = try await ollama.models()
            ollamaModels = models
            if !models.contains(selectedOllamaModel) {
                selectedOllamaModel = models.first ?? ""
            }
            ollamaStatus = models.isEmpty ? "No text-generation models found" : "\(models.count) local text models"
        } catch {
            ollamaModels = []
            selectedOllamaModel = ""
            ollamaStatus = "Ollama unavailable on port 11434"
        }
    }

    @discardableResult
    func generateText(for mode: InstrumentMode, model modelName: String? = nil, prompt: String? = nil) async throws -> String {
        guard mode == .speak || mode == .sing else {
            throw ChimeraError(message: "Ollama text generation is available in Speak and Sing.")
        }
        if ollamaBusy { throw ChimeraError(message: "An Ollama generation is already running.") }
        if ollamaModels.isEmpty { await refreshOllamaModels() }
        if let modelName {
            guard ollamaModels.contains(modelName) else {
                throw ChimeraError(message: "Ollama model \(modelName) is not installed with text-generation support.")
            }
            selectedOllamaModel = modelName
        }
        if let prompt { ollamaPrompt = prompt }
        guard !selectedOllamaModel.isEmpty else {
            throw ChimeraError(message: "No local Ollama text-generation model is available.")
        }
        ollamaBusy = true
        defer { ollamaBusy = false }
        do {
            let text = try await ollama.generateEnglish(prompt: ollamaPrompt, model: selectedOllamaModel, mode: mode)
            if mode == .speak {
                speechText = text
                speechUsesIPA = false
            } else {
                lyrics = text
                rebuildSyllables()
            }
            ollamaStatus = "Plain English generated by \(selectedOllamaModel)"
            return text
        } catch {
            ollamaStatus = error.localizedDescription
            throw error
        }
    }

    func stopAll() {
        stopSinging()
        audio?.stopCall()
        setBeatPlaying(false)
        heldNotes = []
        hold = false
        audio?.setGate(0)
        remote?.stop()
    }

    private func tick() {
        tickCount += 1
        if mode == .bestiary {
            creatureTelemetry = audio?.creatureTelemetry() ?? CreatureTelemetry()
        } else {
            telemetry = audio?.telemetry() ?? VoiceTelemetry()
            beatPlayhead = mode == .beatbox && beatPlaying ? audio?.beatStep() ?? -1 : -1
            updateSongPlayback()
            if tickCount % 3 == 0 { refreshGeometry() }
        }
        headEngineRunning = audio?.engineIsRunning ?? false
        headRenderedFrames = audio?.renderedFrames ?? 0
        if servesHeadStream {
            headStream.publish(headTelemetryFrame())
        }
    }

    private func updateSongPlayback() {
        guard playingSong != nil else { return }
        let now = telemetry.clock - speechPlanOffset
        songPlayhead = max(0, now)
        if now > speechPlanEnd + 0.25 {
            playingSong = nil
            songNoteIndex = -1
            songSyllable = nil
            return
        }
        let secondsPerBeat = 60 / scheduledSongBPM
        songNoteIndex = scheduledSongNotes.firstIndex {
            let start = 0.35 + $0.start * secondsPerBeat
            let end = start + $0.duration * secondsPerBeat
            return now >= start && now < end
        } ?? -1
        songSyllable = scheduledSongNotes.indices.contains(songNoteIndex) ? scheduledSongNotes[songNoteIndex].lyric : nil
    }

    private func headTelemetryFrame() -> HeadTelemetryFrame {
        HeadTelemetryFrame(
            source: sourceName,
            instanceID: instanceID,
            projectID: projectID,
            projectName: projectName,
            timestamp: Date().timeIntervalSince1970,
            body: bodyMix,
            artic: HumanArtic(values: telemetry.artic, fallback: artic),
            frame: frame,
            voiceTelemetry: telemetry,
            playing: hold || !heldNotes.isEmpty || beatPlaying || playingSong != nil || sounding != nil || telemetry.gate > 0.01,
            active: isStarted,
            beatStep: beatPlayhead,
            beatPlaying: beatPlaying,
            bodyScale: bodyScale,
            engineRunning: audio?.engineIsRunning ?? false,
            renderedFrames: audio?.renderedFrames ?? 0,
            whisperEnabled: whisperEnabled
        )
    }

    private func applyRemoteFrame(_ remoteFrame: HeadTelemetryFrame) {
        telemetry = remoteFrame.voiceTelemetry
        frame = remoteFrame.frame
        if whisperEnabled != remoteFrame.whisperEnabled {
            applyingRemoteWhisper = true
            if remoteFrame.whisperEnabled {
                voicedBeforeWhisper = source.voiced
                whisperEnabled = true
                if source.voiced { source.voiced = false }
            } else {
                whisperEnabled = false
                if !source.voiced { source.voiced = voicedBeforeWhisper }
            }
            applyingRemoteWhisper = false
        }
        if bodyMix != remoteFrame.body {
            bodyMix = remoteFrame.body
            scheduleBodyModel(remoteFrame.body)
        }
        isStarted = remoteFrame.active
        headEngineRunning = remoteFrame.engineRunning
        headRenderedFrames = remoteFrame.renderedFrames
        beatPlayhead = remoteFrame.beatStep
        beatPlaying = remoteFrame.beatPlaying
        updateSongPlayback()
        remoteTickCount += 1
        if remoteTickCount % 3 == 0, let airway {
            let liveArtic = HumanArtic(values: telemetry.artic, fallback: artic)
            transfer = try? api.transfer(model: airway.model, artic: liveArtic)
        }
    }

    private func refreshGeometry() {
        guard let airway else { return }
        do {
            let liveArtic = HumanArtic(values: telemetry.artic, fallback: artic)
            frame = try api.frame(model: airway.model, artic: liveArtic)
            if tickCount % 6 == 0 || transfer == nil {
                transfer = try api.transfer(model: airway.model, artic: liveArtic)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func modeChanged(from oldValue: InstrumentMode) {
        guard oldValue != mode else { return }
        heldNotes = []
        hold = false
        if oldValue == .speak { stopSpeech() }
        if oldValue == .sing { stopSinging() }
        if oldValue == .beatbox { setBeatPlaying(false) }
        do {
            if mode == .bestiary {
                try setupCreature()
            } else if oldValue == .bestiary {
                audio?.setHuman()
                creatureInfo = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        updateGate()
        refreshGeometry()
    }

    private func setupCreature() throws {
        let info = try audio?.setCreature(selectedCreatureID, params: creatureParams[selectedCreatureID] ?? [:])
        creatureInfo = info
    }

    private func updateGate() {
        let active = mode != .sing && (hold || !heldNotes.isEmpty)
        audio?.setGate(active ? 1 : 0)
        remote?.setGate(active)
    }

    private func singNoteOn(_ midi: Int) {
        if songSyllables.isEmpty { rebuildSyllables() }
        guard !songSyllables.isEmpty else { return }
        let syllable = songSyllables[syllableCursor % songSyllables.count]
        singSyllableOn(syllable, midi: midi)
        syllableCursor = (syllableCursor + 1) % songSyllables.count
    }

    func singSyllableOn(_ syllable: Syllable, midi: Int) {
        stopSinging()
        startAudio()
        let tag = nextTag
        nextTag += 2
        do {
            let gestures = try api.planNoteOn(syllable, midi: midi, body: bodyMix, vibrato: vibrato, tag: tag)
            audio?.schedule(gestures, controlKeys: controlKeys, lead: 0, replace: false)
            sounding = (syllable, midi, tag)
            songSyllable = syllable.text
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func singNoteOff(_ midi: Int) {
        guard let sounding, sounding.midi == midi else { return }
        audio?.release(sounding.tag)
        audio?.release(sounding.tag + 1)
        do {
            let gestures = try api.planNoteOff(sounding.syllable, midi: midi, body: bodyMix)
            audio?.schedule(gestures, controlKeys: controlKeys, lead: 0, replace: false)
        } catch {
            lastError = error.localizedDescription
        }
        self.sounding = nil
    }

    var bodyScale: Double {
        airway?.body.scale ?? 1
    }

    private var controlKeys: [String] {
        (catalog?.articKeys ?? []) + ["abduction", "closure", "breath", "f0", "vibrato"]
    }

    private func creatureFrequency(midi: Int, param: ParamDef) -> Double {
        let base = 440 * pow(2, Double(midi - 69) / 12)
        let shift = pow(2, round(log2(sqrt(param.min * param.max) / 261.6256)))
        return min(param.max, max(param.min, base * shift))
    }
}

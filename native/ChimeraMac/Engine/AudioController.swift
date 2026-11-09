import AVFoundation
import Foundation

final class AudioController {
    let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var handle: ChimeraHandle
    private var sourceNode: AVAudioSourceNode?
    private var creatureInfo: CreatureInfo?
    private var renderedFrameCount = 0

    var engineIsRunning: Bool { engine.isRunning }
    var renderedFrames: Int { withHandle { _ in renderedFrameCount } }

    init() throws {
        guard let handle = engine_new(sampleRate) else {
            throw ChimeraError(message: "The CHIMERA engine could not be created.")
        }
        self.handle = handle

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            engine_free(handle)
            throw ChimeraError(message: "A 48 kHz audio format could not be created.")
        }
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, buffers in
            self?.render(frameCount: frameCount, buffers: buffers) ?? noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    deinit {
        engine.stop()
        engine_free(handle)
    }

    func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    func setVolume(_ value: Double) {
        engine.mainMixerNode.outputVolume = Float(value)
    }

    func setSource(_ source: VoiceSource) {
        withHandle { handle in
            guard let values = engine_values(handle) else { return }
            values.initialize(repeating: .nan, count: 32)
            for (index, value) in source.patchValues.enumerated() {
                values[index] = value
            }
            engine_set_source(handle)
        }
    }

    func setArtic(_ artic: HumanArtic, tipFree: Bool) {
        withHandle { handle in
            guard let values = engine_values(handle) else { return }
            values.initialize(repeating: .nan, count: 32)
            for (index, value) in artic.values.enumerated() {
                values[index] = value
            }
            engine_set_artic(handle, tipFree ? 1 : 0)
        }
    }

    func setBody(_ body: BodyMix) {
        withHandle { handle in
            engine_set_body(handle, body.female, body.child)
        }
    }

    func setGate(_ level: Double) {
        withHandle { engine_set_gate($0, level) }
    }

    func stopSpeech() {
        withHandle { engine_stop_speech($0) }
    }

    func release(_ tag: Double) {
        withHandle { engine_release($0, tag) }
    }

    @discardableResult
    func schedule(_ gestures: [Gesture], controlKeys: [String], lead: Double = 0.04, replace: Bool = true) -> Double {
        withHandle { handle in
            guard let records = engine_records(handle) else { return 0 }
            let count = min(gestures.count, 4_000)
            for index in 0..<count {
                writeGesture(gestures[index], at: records + index * 272, controlKeys: controlKeys)
            }
            return engine_schedule(handle, count, lead, replace ? 1 : 0)
        }
    }

    func telemetry() -> VoiceTelemetry {
        withHandle { handle in
            guard let pointer = engine_telemetry(handle) else { return VoiceTelemetry() }
            let header = Array(UnsafeBufferPointer(start: pointer, count: 16))
            let nArtic = Int(header[11])
            let nPh = Int(header[12])
            let nOr = Int(header[13])
            let nScope = Int(header[14])
            var offset = 16

            func read(_ count: Int) -> [Double] {
                let values = Array(UnsafeBufferPointer(start: pointer + offset, count: count))
                offset += count
                return values
            }

            var result = VoiceTelemetry()
            result.phLen = header[0]
            result.orLen = header[1]
            result.velumPort = header[2]
            result.f0 = header[3]
            result.voicing = header[4]
            result.lungPressure = header[5]
            result.outRMS = header[6]
            result.gate = header[9]
            result.clock = header[10]
            result.artic = read(nArtic)
            result.phAreas = read(nPh)
            result.orAreas = read(nOr)
            result.pressure = read(nPh + nOr)
            result.flow = read(nPh + nOr)
            result.glottalArea = read(nScope)
            result.glottalFlow = read(nScope)
            return result
        }
    }

    func setBeat(steps: [BeatStep?]? = nil, bpm: Double? = nil, swing: Double? = nil, playing: Bool? = nil) {
        withHandle { handle in
            if let steps, let records = engine_records(handle) {
                let count = min(steps.count, 128)
                for index in 0..<count {
                    writeStep(steps[index], at: records + index * 48)
                }
                engine_set_beat(handle, 1, count, bpm ?? .nan, swing ?? .nan, playing == nil ? 2 : (playing == true ? 1 : 0))
            } else {
                engine_set_beat(handle, 0, 0, bpm ?? .nan, swing ?? .nan, playing == nil ? 2 : (playing == true ? 1 : 0))
            }
        }
    }

    func beatHit(_ step: BeatStep) {
        withHandle { handle in
            guard let records = engine_records(handle) else { return }
            writeStep(step, at: records)
            engine_beat_hit(handle)
        }
    }

    func beatStep() -> Int {
        withHandle { Int(engine_beat_step($0)) }
    }

    func setCreature(_ id: String, params: [String: Double]) throws -> CreatureInfo {
        try withHandle { handle in
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "params": params])
            let status = data.withUnsafeBytes { bytes -> UInt32 in
                engine_set_creature(handle, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
            }
            let result = Data(bytes: chimera_result_ptr(), count: chimera_result_len())
            if status != 0 {
                let object = (try? JSONSerialization.jsonObject(with: result)) as? [String: String]
                throw ChimeraError(message: object?["error"] ?? "The creature could not be selected.")
            }
            let info = try JSONDecoder().decode(CreatureInfo.self, from: result)
            creatureInfo = info
            return info
        }
    }

    func setHuman() {
        withHandle { handle in
            engine_set_human(handle)
            creatureInfo = nil
        }
    }

    func setCreatureParam(index: Int, value: Double) {
        withHandle { engine_creature_param($0, index, value) }
    }

    func playCall(index: Int, pitch: Double? = nil) {
        withHandle { engine_play_call($0, index, pitch ?? .nan, .nan) }
    }

    func stopCall() {
        withHandle { engine_stop_call($0) }
    }

    func creatureTelemetry() -> CreatureTelemetry {
        withHandle { handle in
            guard let info = creatureInfo, let pointer = engine_creature_telemetry(handle) else {
                return CreatureTelemetry()
            }
            let paramCount = info.params.count
            let tubeValueCount = info.tubes.reduce(0) { $0 + $1.n * 2 }
            let sourceCount = info.sources.count
            let values = Array(UnsafeBufferPointer(start: pointer, count: 4 + paramCount + tubeValueCount + sourceCount))
            var result = CreatureTelemetry()
            result.gate = values[0]
            result.outRMS = values[1]
            result.clock = values[2]
            result.call = Int(values[3])
            result.params = Array(values[4..<4 + paramCount])
            var offset = 4 + paramCount
            for tube in info.tubes {
                let areas = Array(values[offset..<offset + tube.n])
                offset += tube.n
                let rms = Array(values[offset..<offset + tube.n])
                offset += tube.n
                result.tubes.append(CreatureTubeTelemetry(name: tube.name, areas: areas, rms: rms))
            }
            return result
        }
    }

    private func withHandle<T>(_ body: (ChimeraHandle) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(handle)
    }

    private func render(frameCount: AVAudioFrameCount, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let output = UnsafeMutableAudioBufferListPointer(buffers)
        for buffer in output {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        lock.lock()
        defer { lock.unlock() }
        var offset = 0
        let total = Int(frameCount)
        renderedFrameCount += total
        while offset < total {
            let count = min(total - offset, 4_096)
            guard let rendered = engine_render(handle, count) else { return noErr }
            for buffer in output {
                guard let data = buffer.mData else { continue }
                let available = min(count, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                let destination = data.assumingMemoryBound(to: Float.self)
                for index in 0..<available {
                    destination[offset + index] = rendered[index]
                }
            }
            offset += count
        }
        return noErr
    }

    private func writeGesture(_ gesture: Gesture, at pointer: UnsafeMutablePointer<UInt8>, controlKeys: [String]) {
        memset(pointer, 0, 272)
        let scalars = [gesture.t0, gesture.t1, gesture.rampIn, gesture.rampOut, gesture.strength, gesture.speed ?? .nan, gesture.releaseHold ?? .nan, gesture.tag ?? .nan]
        for (index, value) in scalars.enumerated() {
            writeDouble(value, at: pointer + index * 8)
        }
        for (index, key) in controlKeys.prefix(22).enumerated() {
            writeDouble(gesture.targets[key] ?? .nan, at: pointer + 64 + index * 8)
        }
        guard let label = gesture.label else {
            pointer[240] = 255
            return
        }
        var bytes: [UInt8] = []
        for character in label {
            let characterBytes = Array(String(character).utf8)
            if bytes.count + characterBytes.count > 24 { break }
            bytes.append(contentsOf: characterBytes)
        }
        pointer[240] = UInt8(bytes.count)
        for (index, byte) in bytes.enumerated() {
            pointer[241 + index] = byte
        }
    }

    private func writeStep(_ step: BeatStep?, at pointer: UnsafeMutablePointer<UInt8>) {
        memset(pointer, 0, 48)
        guard let step else {
            pointer[0] = 255
            writeDouble(.nan, at: pointer + 32)
            writeDouble(.nan, at: pointer + 40)
            return
        }
        var bytes: [UInt8] = []
        for character in step.id {
            let characterBytes = Array(String(character).utf8)
            if bytes.count + characterBytes.count > 24 { break }
            bytes.append(contentsOf: characterBytes)
        }
        pointer[0] = UInt8(bytes.count)
        for (index, byte) in bytes.enumerated() {
            pointer[1 + index] = byte
        }
        writeDouble(step.note ?? .nan, at: pointer + 32)
        writeDouble(step.accent ?? .nan, at: pointer + 40)
    }

    private func writeDouble(_ value: Double, at pointer: UnsafeMutablePointer<UInt8>) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { bytes in
            pointer.update(from: bytes.bindMemory(to: UInt8.self).baseAddress!, count: 8)
        }
    }
}

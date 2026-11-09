import CoreMIDI
import SwiftUI

@MainActor
final class MIDIInputController: ObservableObject {
    let clientName: String

    init(clientName: String) {
        self.clientName = clientName
    }

    @Published private(set) var enabled = false
    @Published private(set) var status = "MIDI off"
    @Published private(set) var sourceNames: [String] = []
    @Published private(set) var lastNote: Int?

    var onNoteOn: ((Int) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    private var client = MIDIClientRef()
    private var input = MIDIPortRef()
    private var connectedSources = Set<MIDIEndpointRef>()

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    func start() {
        guard input == 0 else { enabled = true; refreshSources(); return }
        if client == 0 {
            let result = MIDIClientCreateWithBlock(clientName as CFString, &client) { [weak self] _ in
                Task { @MainActor in self?.refreshSources() }
            }
            guard result == noErr else {
                status = "MIDI client error \(result)"
                return
            }
        }
        let result = MIDIInputPortCreateWithProtocol(client, "Lyric notes" as CFString, ._1_0, &input) { [weak self] packets, _ in
            let messages = Self.messages(from: packets)
            Task { @MainActor in
                guard let self, self.enabled else { return }
                for message in messages {
                    self.lastNote = message.note
                    if message.on { self.onNoteOn?(message.note) } else { self.onNoteOff?(message.note) }
                }
            }
        }
        guard result == noErr else {
            status = "MIDI input error \(result)"
            return
        }
        enabled = true
        refreshSources()
    }

    func stop() {
        if input != 0 {
            for source in connectedSources { MIDIPortDisconnectSource(input, source) }
            MIDIPortDispose(input)
        }
        connectedSources.removeAll()
        input = MIDIPortRef()
        enabled = false
        sourceNames = []
        lastNote = nil
        status = "MIDI off"
    }

    private func refreshSources() {
        guard input != 0 else { return }
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for index in 0..<count {
            let source = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr {
                names.append(name?.takeUnretainedValue() as String? ?? "MIDI source \(index + 1)")
            } else {
                names.append("MIDI source \(index + 1)")
            }
            if !connectedSources.contains(source) {
                if MIDIPortConnectSource(input, source, nil) == noErr { connectedSources.insert(source) }
            }
        }
        sourceNames = names.sorted()
        status = names.isEmpty ? "MIDI on / no sources" : "MIDI on / \(names.count) source\(names.count == 1 ? "" : "s")"
    }

    private nonisolated static func messages(from packets: UnsafePointer<MIDIEventList>) -> [(note: Int, on: Bool)] {
        var output: [(note: Int, on: Bool)] = []
        var packet = packets.pointee.packet
        for _ in 0..<packets.pointee.numPackets {
            var words = packet.words
            let word = withUnsafeBytes(of: &words) { $0.loadUnaligned(as: UInt32.self) }
            let messageType = (word >> 28) & 0x0f
            let status = UInt8((word >> 16) & 0xff)
            let command = status & 0xf0
            if messageType == 0x02, command == 0x90 || command == 0x80 {
                let note = Int((word >> 8) & 0x7f)
                let velocity = UInt8(word & 0xff)
                output.append((note, command == 0x90 && velocity > 0))
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
        return output
    }

    deinit {
        if client != 0 { MIDIClientDispose(client) }
    }
}

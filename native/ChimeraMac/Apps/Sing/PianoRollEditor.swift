import SwiftUI

private enum SingDragMode {
    case move
    case resize
}

private struct SingDragState {
    let id: UUID
    let mode: SingDragMode
    let note: SingNote
}

struct PianoRollEditor: View {
    @ObservedObject var model: InstrumentModel
    @Binding var selectedID: UUID?
    @State private var drag: SingDragState?

    private let lowPitch = 48
    private let highPitch = 76
    private let left = 48.0
    private let top = 22.0
    private let bottom = 20.0

    var body: some View {
        Screen(title: "PIANO ROLL", subtitle: "DRAG TO MOVE / RIGHT EDGE TO RESIZE / ONE SYLLABLE PER NOTE") {
            Canvas { context, size in
                let beatWidth = self.beatWidth(size)
                let rowHeight = self.rowHeight(size)
                let endBeat = self.endBeat
                drawGrid(context: context, size: size, beatWidth: beatWidth, rowHeight: rowHeight, endBeat: endBeat)
                let currentID = currentNoteID
                for note in model.songNotes {
                    let rect = noteRect(note, size: size, beatWidth: beatWidth, rowHeight: rowHeight)
                    let selected = note.id == selectedID
                    let current = note.id == currentID
                    let missing = note.lyric.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let color = missing ? Phosphor.red : current ? Phosphor.white : selected ? Phosphor.amber : Phosphor.green
                    context.fill(Path(rect), with: .color(color.opacity(current ? 0.22 : 0.09)))
                    context.stroke(Path(rect), with: .color(color), lineWidth: current ? 2 : selected ? 1.7 : 1.1)
                    var resize = Path()
                    resize.move(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 2))
                    resize.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 2))
                    context.stroke(resize, with: .color(color.opacity(0.8)), lineWidth: 1)
                    let lyric = missing ? "MISSING LYRIC" : note.lyric.uppercased()
                    if rect.width > 24 {
                        context.draw(
                            Text(lyric).font(.system(size: 9, design: .monospaced)).foregroundStyle(color),
                            at: CGPoint(x: rect.minX + 4, y: rect.minY - 4),
                            anchor: .leading
                        )
                    }
                }
                if model.playingSong != nil {
                    let beat = (model.songPlayhead - 0.35) * model.songBPM / 60
                    let x = left + max(0, beat) * beatWidth
                    if x <= size.width {
                        var playhead = Path()
                        playhead.move(to: CGPoint(x: x, y: 4))
                        playhead.addLine(to: CGPoint(x: x, y: size.height - bottom))
                        context.stroke(playhead, with: .color(Phosphor.white), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    }
                }
            }
            .frame(minHeight: 330)
            .background(Color.black)
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { canvasSize = geometry.size }
                        .onChange(of: geometry.size) { _, size in canvasSize = size }
                }
                .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard drag == nil else {
                            updateDrag(value)
                            return
                        }
                        guard let hit = hitNote(at: value.startLocation) else {
                            selectedID = nil
                            return
                        }
                        selectedID = hit.note.id
                        drag = SingDragState(id: hit.note.id, mode: hit.resize ? .resize : .move, note: hit.note)
                        updateDrag(value)
                    }
                    .onEnded { _ in drag = nil }
            )
            .accessibilityLabel("Editable piano roll. Select a note to edit its pitch, start, duration and lyric.")
        }
    }

    private var endBeat: Double {
        max(16, (model.songNotes.map { $0.start + $0.duration }.max() ?? 0) + 2).rounded(.up)
    }

    private var currentNoteID: UUID? {
        let notes = model.songNotes.sorted { $0.start < $1.start }
        guard notes.indices.contains(model.songNoteIndex) else { return nil }
        return notes[model.songNoteIndex].id
    }

    private func beatWidth(_ size: CGSize) -> Double {
        max(1, (size.width - left - 12) / endBeat)
    }

    private func rowHeight(_ size: CGSize) -> Double {
        max(3, (size.height - top - bottom) / Double(highPitch - lowPitch + 1))
    }

    private func noteRect(_ note: SingNote, size: CGSize, beatWidth: Double, rowHeight: Double) -> CGRect {
        let x = left + note.start * beatWidth
        let y = top + Double(highPitch - note.midi) * rowHeight
        return CGRect(x: x, y: y + 1, width: max(8, note.duration * beatWidth), height: max(4, rowHeight - 2))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, beatWidth: Double, rowHeight: Double, endBeat: Double) {
        for pitch in lowPitch...highPitch {
            let y = top + Double(highPitch - pitch) * rowHeight + rowHeight / 2
            var line = Path()
            line.move(to: CGPoint(x: left, y: y))
            line.addLine(to: CGPoint(x: size.width - 8, y: y))
            context.stroke(line, with: .color(Phosphor.blue.opacity(pitch % 12 == 0 ? 0.48 : 0.13)), lineWidth: pitch % 12 == 0 ? 1 : 0.5)
            if pitch % 12 == 0 {
                context.draw(
                    Text(singNoteName(pitch)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Phosphor.blue),
                    at: CGPoint(x: 6, y: y + 3),
                    anchor: .leading
                )
            }
        }
        for beat in 0...Int(endBeat) {
            let x = left + Double(beat) * beatWidth
            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: size.height - bottom))
            context.stroke(line, with: .color(Phosphor.blue.opacity(beat % 4 == 0 ? 0.45 : 0.16)), lineWidth: 1)
            if beat % 4 == 0 {
                context.draw(
                    Text("\(beat + 1)").font(.system(size: 8, design: .monospaced)).foregroundStyle(Phosphor.blue),
                    at: CGPoint(x: x + 3, y: 9),
                    anchor: .leading
                )
            }
        }
    }

    private func hitNote(at point: CGPoint) -> (note: SingNote, resize: Bool)? {
        guard let size = canvasSize else { return nil }
        let beatWidth = beatWidth(size)
        let rowHeight = rowHeight(size)
        for note in model.songNotes.reversed() {
            let rect = noteRect(note, size: size, beatWidth: beatWidth, rowHeight: rowHeight)
            if rect.insetBy(dx: -3, dy: -3).contains(point) {
                return (note, point.x >= rect.maxX - 8)
            }
        }
        return nil
    }

    @State private var canvasSize: CGSize?

    private func updateDrag(_ value: DragGesture.Value) {
        guard let drag, let size = canvasSize else { return }
        var note = drag.note
        let beatDelta = Double(value.translation.width) / beatWidth(size)
        switch drag.mode {
        case .move:
            note.start = max(0, (drag.note.start + beatDelta).rounded())
            let pitchDelta = Int((-Double(value.translation.height) / rowHeight(size)).rounded())
            note.midi = min(highPitch, max(lowPitch, drag.note.midi + pitchDelta))
        case .resize:
            note.duration = min(32, max(0.25, (drag.note.duration + beatDelta).rounded()))
        }
        model.updateSongNote(note)
    }
}

func singNoteName(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return names[((midi % 12) + 12) % 12] + "\(midi / 12 - 1)"
}

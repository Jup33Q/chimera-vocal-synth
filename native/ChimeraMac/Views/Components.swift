import SwiftUI

enum Phosphor {
    static let blue = Color(red: 0.12, green: 0.58, blue: 1)
    static let amber = Color(red: 1, green: 0.56, blue: 0.12)
    static let green = Color(red: 0.22, green: 1, blue: 0.58)
    static let red = Color(red: 1, green: 0.24, blue: 0.28)
    static let pink = Color(red: 1, green: 0.32, blue: 0.68)
    static let white = Color(red: 0.85, green: 0.92, blue: 1)
}

struct Screen<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Phosphor.blue)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .background(Color(red: 0.004, green: 0.009, blue: 0.014))
        .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.38), lineWidth: 1))
        .shadow(color: Phosphor.blue.opacity(0.12), radius: 5)
    }
}

struct InstrumentSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var color: Color = Phosphor.green

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
                Text(String(format: "%.2f%@", value, unit))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color)
            }
            Slider(value: $value, in: range)
                .tint(color)
                .controlSize(.small)
        }
    }
}

struct RotaryKnob: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var color: Color = Phosphor.green
    var logarithmic = false
    var format: (Double) -> String = { String(Int($0.rounded())) }
    @State private var dragStart: Double?

    var body: some View {
        let position = normalized(value)
        let angle = Double.pi * (0.75 + 1.5 * position)
        VStack(spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * 0.38
                    for index in 0...12 {
                        let tickAngle = Double.pi * (0.75 + 1.5 * Double(index) / 12)
                        var tick = Path()
                        tick.move(to: CGPoint(x: center.x + cos(tickAngle) * (radius + 6), y: center.y + sin(tickAngle) * (radius + 6)))
                        tick.addLine(to: CGPoint(x: center.x + cos(tickAngle) * (radius + 10), y: center.y + sin(tickAngle) * (radius + 10)))
                        context.stroke(tick, with: .color(color.opacity(index <= Int(position * 12) ? 0.8 : 0.3)), lineWidth: 1)
                    }
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color.opacity(0.35)), lineWidth: 1.2)
                    var progress = Path()
                    progress.addArc(center: center, radius: radius, startAngle: .radians(Double.pi * 0.75), endAngle: .radians(angle), clockwise: false)
                    context.stroke(progress, with: .color(color), lineWidth: 2)
                    var needle = Path()
                    needle.move(to: center)
                    needle.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.68, y: center.y + sin(angle) * radius * 0.68))
                    context.stroke(needle, with: .color(color), lineWidth: 1.8)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(color))
                }
                .frame(width: 112, height: 112)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let start = dragStart ?? value
                            if dragStart == nil { dragStart = start }
                            let delta = Double(-gesture.translation.height + gesture.translation.width * 0.35) / 150
                            setNormalized(delta, original: start)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .accessibilityLabel(label)
                .accessibilityValue(format(value))
                .accessibilityAdjustableAction { direction in
                    let step = (logarithmic ? log(range.upperBound / range.lowerBound) : (range.upperBound - range.lowerBound)) * (direction == .increment ? 0.02 : -0.02)
                    if logarithmic {
                        value = min(range.upperBound, max(range.lowerBound, exp(log(value) + step)))
                    } else {
                        value = min(range.upperBound, max(range.lowerBound, value + step))
                    }
                }
            }
            Text(format(value))
                .font(.system(size: 30, weight: .light, design: .monospaced))
                .foregroundStyle(color)
            Text(unit.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func normalized(_ value: Double) -> Double {
        if logarithmic {
            return min(1, max(0, log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)))
        }
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private func setNormalized(_ position: Double, original: Double) {
        let next = normalized(original) + position
        let clamped = min(1, max(0, next))
        value = logarithmic
            ? exp(log(range.lowerBound) + clamped * log(range.upperBound / range.lowerBound))
            : range.lowerBound + clamped * (range.upperBound - range.lowerBound)
    }
}

struct Chip: View {
    let title: String
    var selected = false
    var color: Color = Phosphor.blue
    let action: () -> Void

    var body: some View {
        Button(title.uppercased(), action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(selected ? Color.black : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? color : Color.clear)
            .overlay(Rectangle().stroke(color.opacity(selected ? 1 : 0.55), lineWidth: 1))
    }
}

struct PianoKeys: View {
    var base = 48
    var count = 17
    let heldNotes: [Int]
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(base..<(base + count), id: \.self) { note in
                PianoKey(
                    note: note,
                    black: [1, 3, 6, 8, 10].contains(note % 12),
                    down: heldNotes.contains(note),
                    onNoteOn: onNoteOn,
                    onNoteOff: onNoteOff
                )
            }
        }
        .frame(height: 92)
    }
}

private struct PianoKey: View {
    let note: Int
    let black: Bool
    let down: Bool
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        Text(noteName)
            .font(.system(size: 9, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 6)
            .foregroundStyle(black ? Phosphor.white : Color.black)
            .background(down ? Phosphor.green : (black ? Color(white: 0.09) : Color(white: 0.76)))
            .overlay(Rectangle().stroke(down ? Phosphor.green : Phosphor.blue.opacity(0.35), lineWidth: 1))
            .overlay(MousePressTarget(onPress: { onNoteOn(note) }, onRelease: { onNoteOff(note) }))
            .accessibilityLabel("MIDI note \(note)")
    }

    private var noteName: String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[note % 12] + "\(note / 12 - 1)"
    }
}

struct MousePressTarget: NSViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeNSView(context: Context) -> MousePressView {
        let view = MousePressView()
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateNSView(_ view: MousePressView, context: Context) {
        view.onPress = onPress
        view.onRelease = onRelease
    }
}

final class MousePressView: NSView {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onPress()
    }

    override func mouseUp(with event: NSEvent) {
        onRelease()
    }
}

struct MIDIInputView: View {
    @ObservedObject var midi: MIDIInputController

    var body: some View {
        HStack(spacing: 12) {
            Toggle("MIDI input", isOn: Binding(
                get: { midi.enabled },
                set: { midi.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Text(midi.status.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(midi.enabled ? Phosphor.green : .secondary)
            if let note = midi.lastNote {
                Text("LAST MIDI \(note)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Phosphor.amber)
            }
            Spacer()
            Text(midi.sourceNames.joined(separator: " · "))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

import SwiftUI

struct VowelMapView: View {
    @EnvironmentObject private var model: InstrumentModel
    @State private var draggedUnit: (x: Double, y: Double)?

    var body: some View {
        Screen(title: "VOWELS", subtitle: "F1 / F2 · CONTINUOUS") {
            GeometryReader { geometry in
                Canvas { context, size in
                    guard let space = model.vowelSpace else { return }
                    let inset: Double = 24
                    func point(_ unit: (x: Double, y: Double)) -> CGPoint {
                        CGPoint(
                            x: inset + unit.x * (size.width - inset * 2),
                            y: inset + unit.y * (size.height - inset * 2)
                        )
                    }

                    let guide = [
                        (300.0, 2_500.0), (320.0, 850.0), (720.0, 1_050.0), (780.0, 1_650.0)
                    ].map { point(space.unitPoint(f1: $0.0, f2: $0.1)) }
                    if let first = guide.first {
                        var path = Path()
                        path.move(to: first)
                        for corner in guide.dropFirst() { path.addLine(to: corner) }
                        path.closeSubpath()
                        context.stroke(path, with: .color(Phosphor.blue.opacity(0.5)), lineWidth: 1)
                    }

                    for vowel in space.points {
                        let center = point(space.unitPoint(f1: vowel.f1, f2: vowel.f2))
                        context.draw(
                            Text(vowel.ipa).font(.system(size: 16, design: .monospaced)).foregroundStyle(Phosphor.blue),
                            at: center
                        )
                    }

                    let measured: (x: Double, y: Double)? = {
                        guard let transfer = model.transfer, transfer.formants.count >= 2 else { return nil }
                        return space.unitPoint(f1: transfer.formants[0], f2: transfer.formants[1])
                    }()
                    if let unit = draggedUnit ?? measured {
                        let center = point(unit)
                        let formants = space.formants(x: unit.x, y: unit.y)
                        let handle = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
                        context.fill(handle, with: .color(Phosphor.green.opacity(0.16)))
                        context.stroke(handle, with: .color(Phosphor.green), lineWidth: 1.5)
                        if let nearest = space.nearest(f1: formants.f1, f2: formants.f2) {
                            context.draw(
                                Text(nearest.ipa).font(.system(size: 17, design: .monospaced)).foregroundStyle(Phosphor.green),
                                at: CGPoint(x: center.x + 22, y: center.y - 12)
                            )
                        }
                    }
                    context.draw(Text("F1").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary), at: CGPoint(x: 12, y: size.height - 10))
                    context.draw(Text("F2").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary), at: CGPoint(x: size.width - 12, y: size.height - 10))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let width = max(1, geometry.size.width - 48)
                            let height = max(1, geometry.size.height - 48)
                            let x = (value.location.x - 24) / width
                            let y = (value.location.y - 24) / height
                            draggedUnit = (x, y)
                            model.setVowelPosition(x: x, y: y)
                        }
                        .onEnded { _ in draggedUnit = nil }
                )
                .accessibilityLabel("Continuous vowel map. Drag to morph between calibrated vowels in the F1 F2 space.")
            }
        }
        .frame(height: 240)
    }
}

import SwiftUI

struct BodyPaletteView: View {
    @ObservedObject var model: InstrumentModel
    @State private var draggedPoint: CGPoint?
    @State private var pendingBody: BodyMix?
    @State private var updateScheduled = false

    var body: some View {
        Screen(title: "AGE / GENDER", subtitle: "CONTINUOUS BODY") {
            GeometryReader { geometry in
                let size = geometry.size
                let male = CGPoint(x: 36, y: size.height - 44)
                let female = CGPoint(x: size.width - 36, y: size.height - 44)
                let child = CGPoint(x: size.width / 2, y: 28)
                let current = draggedPoint ?? point(for: model.bodyMix, size: size)

                ZStack {
                    Canvas { context, _ in
                        var triangle = Path()
                        triangle.move(to: male)
                        triangle.addLine(to: female)
                        triangle.addLine(to: child)
                        triangle.closeSubpath()
                        context.fill(triangle, with: .color(Color.black.opacity(0.6)))
                        context.fill(triangle, with: .radialGradient(
                            Gradient(colors: [BodyPalette.color(.male).opacity(0.65), .clear]),
                            center: male, startRadius: 0, endRadius: size.width * 0.72
                        ))
                        context.fill(triangle, with: .radialGradient(
                            Gradient(colors: [BodyPalette.color(.female).opacity(0.65), .clear]),
                            center: female, startRadius: 0, endRadius: size.width * 0.72
                        ))
                        context.fill(triangle, with: .radialGradient(
                            Gradient(colors: [BodyPalette.color(.child).opacity(0.65), .clear]),
                            center: child, startRadius: 0, endRadius: size.width * 0.72
                        ))
                        context.stroke(triangle, with: .color(BodyPalette.color(model.bodyMix)), lineWidth: 1.4)

                        let center = CGPoint(x: size.width / 2, y: (size.height - 44 + 28) / 2)
                        for (vertex, color) in [(male, Phosphor.blue), (female, Phosphor.red), (child, Phosphor.green)] {
                            var axis = Path()
                            axis.move(to: center)
                            axis.addLine(to: vertex)
                            context.stroke(axis, with: .color(color.opacity(0.35)), lineWidth: 0.8)
                        }
                        let handle = Path(ellipseIn: CGRect(x: current.x - 8, y: current.y - 8, width: 16, height: 16))
                        context.fill(handle, with: .color(Color.black))
                        context.stroke(handle, with: .color(BodyPalette.color(model.bodyMix)), lineWidth: 2)
                    }

                    Button("Child") { select(.child) }
                        .foregroundStyle(Phosphor.green)
                        .position(x: child.x, y: 10)
                    Button("Male") { select(.male) }
                        .foregroundStyle(Phosphor.blue)
                        .position(x: male.x + 22, y: size.height - 14)
                    Button("Female") { select(.female) }
                        .foregroundStyle(Phosphor.red)
                        .position(x: female.x - 26, y: size.height - 14)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = bodyPoint(for: value.location, size: size)
                            draggedPoint = clamped
                            schedule(bodyMix(for: clamped, size: size))
                        }
                        .onEnded { value in
                            let clamped = bodyPoint(for: value.location, size: size)
                            draggedPoint = nil
                            pendingBody = nil
                            model.setBody(bodyMix(for: clamped, size: size))
                        }
                )
                .accessibilityLabel("Continuous age and gender palette. Drag between male, female and child bodies.")
            }
        }
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320, minHeight: 280, idealHeight: 320, maxHeight: 380)
    }

    private func select(_ body: BodyMix) {
        draggedPoint = nil
        pendingBody = nil
        model.setBody(body)
    }

    private func schedule(_ body: BodyMix) {
        pendingBody = body
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30.0) {
            guard let body = pendingBody else {
                updateScheduled = false
                return
            }
            pendingBody = nil
            updateScheduled = false
            model.setBody(body)
        }
    }

    private func point(for body: BodyMix, size: CGSize) -> CGPoint {
        let childWeight = min(1, max(0, body.child))
        let femaleWeight = (1 - childWeight) * min(1, max(0, body.female))
        let top: Double = 28
        let bottom = size.height - 44
        return CGPoint(
            x: 36 + femaleWeight * (size.width - 72) + childWeight * (size.width / 2 - 36),
            y: bottom - childWeight * (bottom - top)
        )
    }

    private func bodyPoint(for location: CGPoint, size: CGSize) -> CGPoint {
        let top: Double = 28
        let bottom = size.height - 44
        let y = min(bottom, max(top, location.y))
        let childWeight = (bottom - y) / (bottom - top)
        let left = 36 + childWeight * (size.width / 2 - 36)
        let right = size.width - 36 - childWeight * (size.width / 2 - 36)
        return CGPoint(x: min(right, max(left, location.x)), y: y)
    }

    private func bodyMix(for point: CGPoint, size: CGSize) -> BodyMix {
        let top: Double = 28
        let bottom = size.height - 44
        let childWeight = min(1, max(0, (bottom - point.y) / (bottom - top)))
        let left = 36 + childWeight * (size.width / 2 - 36)
        let right = size.width - 36 - childWeight * (size.width / 2 - 36)
        let femaleWeight = min(1 - childWeight, max(0, (point.x - left) / max(1, right - left) * (1 - childWeight)))
        let femaleAxis = childWeight < 0.9999 ? femaleWeight / (1 - childWeight) : 0
        return BodyMix(female: femaleAxis, child: childWeight)
    }
}

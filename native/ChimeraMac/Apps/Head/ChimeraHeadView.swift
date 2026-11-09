import SwiftUI

struct ChimeraHeadView: View {
    let head: HeadModel
    @ObservedObject var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            HeadHeader(head: head, model: model)
            Screen(title: "LIVE VOCAL TRACT", subtitle: "HEAD AUDIO + MODEL HOST") {
                ZStack {
                    HeadCanvas(
                        frame: model.frame,
                        telemetry: model.telemetry,
                        bodyScale: model.bodyScale,
                        bodyMix: model.bodyMix,
                        camera: head.camera,
                        animationEnabled: head.animationEnabled,
                        particlesEnabled: head.particlesEnabled,
                        visualStore: head.visualStore
                    )
                    HeadOverlay(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HeadFooter(head: head, clients: model.headStreamClientCount)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task {
            model.prepare()
            head.start(model: model)
        }
    }
}

private struct HeadHeader: View {
    let head: HeadModel
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack {
            Text("CHIMERA HEAD")
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Phosphor.blue)
            Text(model.headDisplayState.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.headPlaying ? Phosphor.green : Phosphor.amber)
            Spacer()
            Text("AUDIO + MODEL 8647 / \(model.headStreamClientCount) CONTROLLERS")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("MCP 127.0.0.1:8647")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Phosphor.blue)
                .textSelection(.enabled)
        }
    }
}

private struct HeadOverlay: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOCAL PHYSICAL MODEL")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Phosphor.blue)
                    Text(model.isStarted ? "Audio online; articulation follows controller input" : "Audio standby; ready for controllers")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("DRAG / PINCH / DOUBLE-CLICK RESET")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.frame == nil {
                Text("WAITING")
                    .font(.system(size: 20, weight: .light, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Phosphor.amber)
            } else if !model.headPlaying {
                Text("STANDBY / LAST VALID GEOMETRY")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.amber)
                    .padding(8)
                    .background(Color.black.opacity(0.8))
                    .overlay(Rectangle().stroke(Phosphor.amber.opacity(0.5)))
            }
            HeadTelemetry(model: model)
        }
        .padding(10)
    }
}

private struct HeadTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 22) {
            HeadReadout(label: "F0 HZ", value: model.telemetry.f0)
            HeadReadout(label: "GATE", value: model.telemetry.gate)
            HeadReadout(label: "OUT RMS", value: model.telemetry.outRMS)
            Spacer()
            Text("TONGUE ROOT \(String(format: "%.2f", model.artic.root))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Phosphor.blue)
        }
        .padding(8)
        .background(Color.black.opacity(0.72))
    }
}

private struct HeadReadout: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}

private struct HeadFooter: View {
    @Bindable var head: HeadModel
    let clients: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("HEAD OWNS AUDIO / CAMERA IS LOCAL / \(clients) NDJSON CLIENTS")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("LKG: \(head.lkgStatus)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(head.lkgHardwareVerified ? Phosphor.green : .secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Text("FOV")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                Slider(value: $head.lkgFov, in: 12...90)
                    .tint(Phosphor.blue)
                    .frame(width: 110)
                    .accessibilityLabel("LKG field of view in degrees")
                Text(String(format: "%.0f°", head.lkgFov))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                Text("FOCUS")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                Slider(value: $head.lkgFocus, in: 20...100)
                    .tint(Phosphor.blue)
                    .frame(width: 130)
                    .accessibilityLabel("LKG focus distance in centimeters")
                Text(String(format: "%.0f CM", head.lkgFocus))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                Text("PARALLAX")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                Slider(value: $head.lkgParallax, in: 0...30)
                    .tint(Phosphor.blue)
                    .frame(width: 130)
                    .accessibilityLabel("LKG parallax in centimeters")
                Text(String(format: "%.1f CM", head.lkgParallax))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                Spacer()
            }
            HStack {
                Spacer()
                Chip(title: head.lkgConnected ? "Disconnect LKG" : "Connect LKG", selected: head.lkgConnected, color: Phosphor.blue) { head.toggleLKG() }
                Chip(title: "Animation", selected: head.animationEnabled, color: Phosphor.green) { head.animationEnabled.toggle() }
                Chip(title: "Particles", selected: head.particlesEnabled, color: Phosphor.amber) { head.particlesEnabled.toggle() }
                Chip(title: "Reset camera", color: Phosphor.blue) { head.camera.reset() }
            }
        }
    }
}

private extension InstrumentModel {
    var headPlaying: Bool {
        isStarted && (hold || !heldNotes.isEmpty || beatPlaying || playingSong != nil || telemetry.gate > 0.01)
    }

    var headDisplayState: String {
        frame == nil ? "Waiting" : headPlaying ? "Live" : "Standby"
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: InstrumentModel
    @State private var yaw = 0.62
    @State private var pitch = 0.2
    @State private var zoom = 1.0
    @State private var yawAtDragStart = 0.62
    @State private var pitchAtDragStart = 0.2
    @State private var zoomAtGestureStart = 1.0
    @State private var orbiting = false
    @State private var zooming = false

    var body: some View {
        VStack(spacing: 12) {
            topBar
            if let error = model.lastError {
                HStack {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Phosphor.red)
                    Spacer()
                    Button("Dismiss") { model.lastError = nil }
                        .foregroundStyle(Phosphor.red)
                }
                .padding(.horizontal, 4)
            }
            HStack(alignment: .top, spacing: 12) {
                Screen(title: model.mode == .bestiary ? "CREATURE AIRWAY" : "VOCAL TRACT 3D", subtitle: "LIVE PHYSICS") {
                    GeometryReader { geometry in
                        ZStack {
                            if model.mode == .bestiary {
                                MetalCanvas(scene: SceneFactory.creature(model.creatureTelemetry, size: geometry.size))
                            } else {
                                MetalCanvas3D(
                                    scene: SceneFactory.anatomy3D(frame: model.frame, telemetry: model.telemetry, bodyScale: model.bodyScale),
                                    yaw: yaw,
                                    pitch: pitch,
                                    zoom: zoom,
                                    bodyScale: model.bodyScale
                                )
                            }
                            VStack {
                                HStack {
                                    Text(model.mode == .bestiary ? "AREA / PRESSURE" : "3D MODEL / DRAG TO ORBIT / PINCH TO ZOOM")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                Spacer()
                                telemetryBar
                            }
                            .padding(8)
                            if !model.isStarted {
                                startOverlay
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(orbitGesture)
                        .simultaneousGesture(zoomGesture)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                yaw = 0.62
                                pitch = 0.2
                                zoom = 1
                            }
                        )
                        .accessibilityLabel("Interactive three-dimensional vocal tract. Drag to orbit, pinch to zoom, double-click to reset.")
                    }
                }
                .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    Group {
                        switch model.mode {
                        case .play: PlayView()
                        case .speak: SpeakView()
                        case .sing: SingView()
                        case .beatbox: BeatboxView()
                        case .bestiary: BestiaryView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 430, maxWidth: 560, maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task {
            model.prepare()
            await model.refreshOllamaModels()
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("CHIMERA")
                    .font(.system(size: 20, weight: .light, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(Phosphor.blue)
                Text("PHYSICAL VOICE SYNTHESIZER")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MCP 127.0.0.1:\(model.mcpPort)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                    .textSelection(.enabled)
                Text(model.isStarted ? "ENGINE ONLINE / 48 KHZ" : "ENGINE STANDBY")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(model.isStarted ? Phosphor.green : Phosphor.amber)
            }
            HStack {
                ForEach(InstrumentMode.allCases) { mode in
                    Chip(title: mode.rawValue, selected: model.mode == mode) { model.mode = mode }
                }
                Spacer()
                ForEach([("MALE", BodyMix.male), ("FEMALE", BodyMix.female), ("CHILD", BodyMix.child)], id: \.0) { name, body in
                    Chip(title: name, selected: model.bodyMix == body, color: Phosphor.white) { model.setBody(body) }
                }
                Slider(value: $model.volume, in: 0...1)
                    .tint(Phosphor.amber)
                    .frame(width: 90)
                    .accessibilityLabel("Output volume")
            }
        }
    }

    private var startOverlay: some View {
        VStack(spacing: 12) {
            Text("AIRWAY READY")
                .font(.system(size: 13, design: .monospaced))
                .tracking(2)
            Chip(title: "Breathe in and start", color: Phosphor.green) { model.startAudio() }
        }
        .padding(24)
        .background(Color.black.opacity(0.88))
        .overlay(Rectangle().stroke(Phosphor.green.opacity(0.5), lineWidth: 1))
    }

    private var telemetryBar: some View {
        HStack {
            if model.mode == .bestiary {
                readout("LEVEL", model.creatureTelemetry.outRMS)
                readout("GATE", model.creatureTelemetry.gate)
                readout("CLOCK", model.creatureTelemetry.clock)
            } else {
                readout("F0 HZ", model.telemetry.f0)
                readout("LUNG", model.telemetry.lungPressure)
                readout("LEVEL", model.telemetry.outRMS)
                readout("GATE", model.telemetry.gate)
            }
            Spacer()
        }
        .padding(7)
        .background(Color.black.opacity(0.72))
    }

    private var orbitGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard model.mode != .bestiary else { return }
                if !orbiting {
                    yawAtDragStart = yaw
                    pitchAtDragStart = pitch
                    orbiting = true
                }
                yaw = yawAtDragStart + Double(value.translation.width) * 0.008
                pitch = min(1.1, max(-1.1, pitchAtDragStart + Double(value.translation.height) * 0.006))
            }
            .onEnded { _ in orbiting = false })
    }

    private var zoomGesture: AnyGesture<MagnificationGesture.Value> {
        AnyGesture(MagnificationGesture()
            .onChanged { value in
                guard model.mode != .bestiary else { return }
                if !zooming {
                    zoomAtGestureStart = zoom
                    zooming = true
                }
                zoom = min(2.4, max(0.55, zoomAtGestureStart * Double(value)))
            }
            .onEnded { _ in
                zoomAtGestureStart = zoom
                zooming = false
            })
    }

    private func readout(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}

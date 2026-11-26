// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/Studio/Sources/SynthApp/StudioSurface.swift
// StudioSurface.swift
// スタジオ機器のプレート・オシロスコープ・精密ロータリーダイアル・モジュールレイアウトを描画するUI

import SwiftUI

private enum SurfaceMaterial {
    static let aluminiumTop = Color(red: 0.165, green: 0.185, blue: 0.210)
    static let aluminium = Color(red: 0.130, green: 0.146, blue: 0.168)
    static let aluminiumBottom = Color(red: 0.098, green: 0.110, blue: 0.128)
    static let bezel = Color(red: 0.055, green: 0.062, blue: 0.074)
    static let glass = Color(red: 0.018, green: 0.034, blue: 0.044)
    static let glassLight = Color(red: 0.045, green: 0.088, blue: 0.102)
    static let dialSkirt = Color(red: 0.075, green: 0.085, blue: 0.098)
    static let dialEdge = Color(red: 0.34, green: 0.38, blue: 0.43)
    static let dialFace = Color(red: 0.24, green: 0.27, blue: 0.31)
    static let dialHighlight = Color(red: 0.46, green: 0.50, blue: 0.56)
    static let dialShade = Color(red: 0.12, green: 0.14, blue: 0.16)
}

struct StudioPlate: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        content
            .background {
                shape.fill(.linearGradient(colors: [SurfaceMaterial.aluminiumTop, SurfaceMaterial.aluminium, SurfaceMaterial.aluminiumBottom],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        // Brushed metal horizontal sheen
                        shape.fill(.linearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.14)],
                                                   startPoint: .top, endPoint: .bottom))
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
            }
            .overlay {
                shape.strokeBorder(.linearGradient(colors: [.white.opacity(0.18), InstrumentFinish.metalEdge.opacity(0.55), .black.opacity(0.55)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.white.opacity(0.045), lineWidth: 0.75)
                    .padding(1)
                    .allowsHitTesting(false)
            }
    }
}

struct StudioScope: View {
    let scope: OutputScope?
    let height: CGFloat

    private let leftTrace = Color(red: 0.49, green: 0.96, blue: 0.85)
    private let rightTrace = Color(red: 0.48, green: 0.71, blue: 0.95)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scope == nil)) { _ in
            let snapshot = scope?.snapshot()
            let peak = snapshot?.samples.reduce(Float.zero) { peak, sample in
                let channelPeak = max(abs(sample.x), abs(sample.y))
                return channelPeak.isFinite ? max(peak, channelPeak) : peak
            } ?? 0
            let scale = max(0.08, min(1, (peak * 10).rounded(.up) / 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(instrumentText("Output waveform", "出力波形", "输出波形"), systemImage: "waveform")
                    Spacer(minLength: 8)
                    Text("±" + scale.formatted(.number.precision(.fractionLength(2))))
                        .foregroundStyle(.white.opacity(0.70))
                    Text("L").foregroundStyle(leftTrace)
                    Text("R").foregroundStyle(rightTrace)
                }
                .font(InstrumentFinish.legend(10))
                Canvas { context, size in
                    for x in 0...8 {
                        let position = size.width * CGFloat(x) / 8
                        let line = Path { path in
                            path.move(to: CGPoint(x: position, y: 0))
                            path.addLine(to: CGPoint(x: position, y: size.height))
                        }
                        context.stroke(line, with: .color(.white.opacity(0.10)), lineWidth: 1)
                    }
                    for y in 0...4 {
                        let position = size.height * CGFloat(y) / 4
                        let line = Path { path in
                            path.move(to: CGPoint(x: 0, y: position))
                            path.addLine(to: CGPoint(x: size.width, y: position))
                        }
                        context.stroke(line, with: .color(.white.opacity(y == 2 ? 0.23 : 0.10)), lineWidth: 1)
                    }
                    guard let snapshot, snapshot.samples.count > 1 else { return }
                    let samples = snapshot.samples
                    let window = min(Int(snapshot.sampleRate * 0.020), samples.count)
                    let start = samples.count - window
                    // Trigger on a positive crossing near the beginning of the window.
                    let search = min(window / 4, 256)
                    let trigger = (start..<(start + search)).first {
                        samples[$0].x <= 0 && samples[$0 + 1].x > 0.001
                    } ?? start
                    let count = min(window - search, samples.count - trigger)
                    guard count > 1 else { return }
                    for channel in [1, 0] {
                        let trace = Path { path in
                            for i in 0..<count {
                                let amplitude = samples[trigger + i][channel]
                                let value = amplitude.isFinite ? min(1, max(-1, CGFloat(amplitude / scale))) : 0
                                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(count - 1),
                                                    y: size.height * (0.5 - value * 0.48))
                                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                            }
                        }
                        let traceColor = channel == 0 ? leftTrace : rightTrace.opacity(0.65)
                        context.stroke(trace, with: .color(traceColor.opacity(0.24)),
                                       lineWidth: channel == 0 ? 4.5 : 3.0)
                        context.stroke(trace, with: .color(traceColor),
                                       lineWidth: channel == 0 ? 1.6 : 1.0)
                    }
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.linearGradient(colors: [SurfaceMaterial.glassLight, SurfaceMaterial.glass, SurfaceMaterial.glass],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        // Subtle sapphire-glass diagonal sheen
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.linearGradient(colors: [.white.opacity(0.065), .clear, .clear],
                                                  startPoint: .topLeading, endPoint: .center))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.linearGradient(colors: [.black.opacity(0.85), .white.opacity(0.16)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            }
            .padding(3)
            .background(SurfaceMaterial.bezel, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.linearGradient(colors: [.white.opacity(0.15), .black.opacity(0.85)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
        }
    }
}

struct StudioDial: View {
    let control: PanelControl
    let changed: () -> Void
    @State private var origin: Double?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    // Background track arc
                    let track = Path { path in
                        path.addArc(center: center, radius: 26.5,
                                    startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    }
                    context.stroke(track, with: .color(.black.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    // Active illuminated value arc
                    if control.normalized > 0.005 {
                        let active = Path { path in
                            path.addArc(center: center, radius: 26.5,
                                        startAngle: .degrees(135),
                                        endAngle: .degrees(135 + control.normalized * 270),
                                        clockwise: false)
                        }
                        context.stroke(active, with: .color(InstrumentFinish.amber.opacity(0.35)),
                                       style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        context.stroke(active, with: .color(InstrumentFinish.amber),
                                       style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    }
                    for tick in 0...20 {
                        let angle = Double(tick) / 20 * 1.5 * .pi + 0.75 * .pi
                        let inside = tick.isMultiple(of: 5) ? 28.0 : 29.0
                        let mark = Path { path in
                            path.move(to: CGPoint(x: center.x + cos(angle) * inside, y: center.y + sin(angle) * inside))
                            path.addLine(to: CGPoint(x: center.x + cos(angle) * 31.0, y: center.y + sin(angle) * 31.0))
                        }
                        context.stroke(mark, with: .color(InstrumentFinish.muted.opacity(tick.isMultiple(of: 5) ? 0.80 : 0.40)), lineWidth: tick.isMultiple(of: 5) ? 1.1 : 0.8)
                    }
                }
                // Knurled outer skirt
                Circle().fill(SurfaceMaterial.dialSkirt).frame(width: 45, height: 45)
                    .overlay {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                            for k in 0..<36 {
                                let a = Double(k) / 36 * 2 * .pi
                                let groove = Path { p in
                                    p.move(to: CGPoint(x: center.x + cos(a) * 20.5, y: center.y + sin(a) * 20.5))
                                    p.addLine(to: CGPoint(x: center.x + cos(a) * 22.4, y: center.y + sin(a) * 22.4))
                                }
                                context.stroke(groove, with: .color(.white.opacity(0.10)), lineWidth: 0.7)
                            }
                        }
                    }
                    .overlay { Circle().strokeBorder(.black.opacity(0.80), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.65), radius: 4, x: 0, y: 3)
                // Machined chamfer ring
                Circle()
                    .fill(.linearGradient(colors: [SurfaceMaterial.dialHighlight, SurfaceMaterial.dialShade, SurfaceMaterial.dialFace],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                // Brushed titanium cap
                Circle()
                    .fill(AngularGradient(colors: [SurfaceMaterial.dialFace, SurfaceMaterial.dialHighlight,
                                                    SurfaceMaterial.dialShade, SurfaceMaterial.dialFace,
                                                    SurfaceMaterial.dialHighlight, SurfaceMaterial.dialFace], center: .center))
                    .overlay {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                            for ring in 1...16 {
                                let radius = CGFloat(ring) * size.width / 34
                                let bounds = CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)
                                let color: Color = ring.isMultiple(of: 3) ? .white : .black
                                context.stroke(Path(ellipseIn: bounds), with: .color(color.opacity(0.14)), lineWidth: 0.45)
                            }
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(hovering || origin != nil ? InstrumentFinish.amber.opacity(0.55) : SurfaceMaterial.dialEdge.opacity(0.65), lineWidth: 0.75)
                    }
                    .frame(width: 36, height: 36)
                Capsule()
                    .fill(InstrumentFinish.amber)
                    .frame(width: 2.5, height: 8)
                    .shadow(color: InstrumentFinish.amber.opacity(0.75), radius: 2)
                    .offset(y: -13.5)
                    .rotationEffect(.degrees(-135 + control.normalized * 270))
            }
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 1).onChanged {
                if origin == nil { origin = control.normalized }
                control.setNormalized((origin ?? control.normalized) - $0.translation.height / 140)
                changed()
            }.onEnded { _ in origin = nil })
            .onTapGesture(count: 2) { control.value.wrappedValue = control.resetValue; changed() }
            Text(control.label).font(InstrumentFinish.legend(9)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.72)
            Text(control.displayValue).font(InstrumentFinish.legend(10)).monospacedDigit()
                .foregroundStyle(InstrumentFinish.muted).lineLimit(1).minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.title)
        .accessibilityValue(control.displayValue)
        .accessibilityAdjustableAction { direction in
            let delta = control.quantized ? 1.0 / 48 : 0.02
            control.setNormalized(control.normalized + (direction == .increment ? delta : -delta))
            changed()
        }
        .help(control.title)
    }
}

struct StudioModules: View {
    let controls: [PanelControl]
    let switches: [PanelSwitch]
    let spectral: [PanelControl]
    let width: CGFloat
    let changed: () -> Void

    private var columns: [[Int]] {
        if width >= 880 { return [[3, 5, 9], [4, 0, 1, 2], [6, 7, 8]] }
        if width >= 570 { return [[3, 4, 5, 9], [6, 7, 8, 0, 1, 2]] }
        return [[3, 4, 5, 6, 7, 8, 0, 1, 2, 9]]
    }
    private let symbols = ["point.3.connected.trianglepath.dotted", "waveform.path", "arrow.left.and.right",
                           "waveform", "waveform", "slider.horizontal.3", "line.3.horizontal.decrease",
                           "chart.xyaxis.line", "speaker.wave.2", "pianokeys"]
    private let titles = [
        ["Poly-Mod", "ポリモッド", "复调调制"], ["LFO", "LFO", "LFO"], ["Wheel modulation", "ホイール変調", "调制轮"],
        ["Oscillator A", "オシレーター A", "振荡器 A"], ["Oscillator B", "オシレーター B", "振荡器 B"],
        ["Mixer", "ミキサー", "混音器"], ["Filter", "フィルター", "滤波器"],
        ["Filter envelope", "フィルター包絡", "滤波包络"], ["Amplifier envelope", "音量包絡", "振幅包络"],
        ["Performance", "演奏設定", "演奏设置"]
    ]

    var body: some View {
        let trackWidth = (width - 6 - CGFloat(columns.count - 1) * 12) / CGFloat(columns.count)
        HStack(alignment: .top, spacing: 12) {
            ForEach(columns.indices, id: \.self) { column in
                LazyVStack(spacing: 12) {
                    ForEach(columns[column], id: \.self) { index in
                        module(index)
                    }
                }
                .frame(width: max(1, trackWidth))
            }
        }
        .foregroundStyle(InstrumentFinish.ink)
        .padding(3)
    }

    @ViewBuilder private func module(_ index: Int) -> some View {
        let section = Rev3.sections[index]
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: symbols[index])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(InstrumentFinish.amber)
                Text(instrumentText(titles[index][0], titles[index][1], titles[index][2]))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .tracking(0.2)
                Rectangle()
                    .fill(.linearGradient(colors: [InstrumentFinish.metalEdge.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                PanelScrew()
            }
            dials(section.knobs.filter { $0 != 25 }.map { controls[$0] })
            if !section.switches.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 5)], spacing: 5) {
                    ForEach(section.switches, id: \.self) { item in
                        StudioSwitch(control: switches[item], changed: changed)
                    }
                }
            }
            if index == 3 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(InstrumentFinish.amber)
                            .frame(width: 5, height: 5)
                            .shadow(color: InstrumentFinish.amber.opacity(0.9), radius: 3)
                        Text("SDS")
                            .font(InstrumentFinish.legend(11))
                            .tracking(1.2)
                            .foregroundStyle(InstrumentFinish.amber)
                        Text("SPECTRAL DYNAMICS")
                            .font(InstrumentFinish.legend(8))
                            .tracking(1.0)
                            .foregroundStyle(InstrumentFinish.muted)
                        Spacer(minLength: 0)
                    }
                    dials(spectral)
                }
                .padding(11)
                .background(
                    LinearGradient(colors: [Color(red: 0.045, green: 0.082, blue: 0.095), Color(red: 0.032, green: 0.056, blue: 0.068)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.linearGradient(colors: [InstrumentFinish.amber.opacity(0.45), InstrumentFinish.amber.opacity(0.12)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(12)
        .modifier(StudioPlate())
    }

    private func dials(_ items: [PanelControl]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 3)], spacing: 9) {
            ForEach(items.indices, id: \.self) { index in
                StudioDial(control: items[index], changed: changed)
            }
        }
    }
}


private struct StudioSwitch: View {
    let control: PanelSwitch
    let changed: () -> Void

    private let ledCore = Color(red: 0.78, green: 1.0, blue: 0.52)
    private let ledHalo = Color(red: 0.28, green: 0.71, blue: 0.06)
    private let lens = Color(red: 0.19, green: 0.22, blue: 0.20)

    var body: some View {
        let isOn = control.value.wrappedValue
        Button {
            control.value.wrappedValue.toggle()
            changed()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Capsule().fill(SurfaceMaterial.bezel)
                        .frame(width: 19, height: 8)
                    Capsule().fill(isOn ? ledCore : lens)
                        .frame(width: 13, height: 4)
                        .shadow(color: isOn ? ledHalo : .clear, radius: 3)
                }
                .accessibilityHidden(true)
                Text(control.label)
                    .font(InstrumentFinish.legend(9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(HardwareButtonStyle(selected: isOn, showsSelectionMark: false))
        .accessibilityLabel(control.title)
        .accessibilityValue(isOn ? instrumentText("On", "オン", "开") : instrumentText("Off", "オフ", "关"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(control.title)
    }
}

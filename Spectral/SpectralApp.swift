import CoreMIDI
import SwiftUI

@main
struct SpectralApp: App {
    #if os(macOS)
    @AppStorage("sdsLanguage") private var language = SpectralLanguage.system
    #endif

    var body: some Scene {
        #if os(macOS)
        Window(Text(verbatim: language.windowTitle), id: "instrument") {
            SpectralView()
                .frame(minWidth: 660, minHeight: 310, maxHeight: 360)
        }
        .defaultSize(width: 960, height: 330)
        .windowResizability(.contentSize)
        #else
        WindowGroup { SpectralView() }
        #endif
    }
}

struct SpectralView: View {
    @StateObject private var audio = SpectralAudio()
    @Environment(\.scenePhase) private var phase
    @AppStorage("sdsLanguage") private var language = SpectralLanguage.system
    @State private var midi = MIDIInput()
    @State private var midiKeys: Set<MIDIKey> = []
    @State private var midiDampers: [MIDIEndpointRef: Int] = [:]
    @State private var midiSoftPedals: Set<MIDIEndpointRef> = []
    @State private var octave = 4
    @State private var velocity = 60.0
    @State private var pedal = 0.0
    @State private var softPedal = false
    @State private var touches: Set<Int> = []
    @State private var accessibilityNotes: [Int: UUID] = [:]
    @State private var info = false
    @State private var visibleNotes = 14
    var playsAudio = true

    private let brass = Color(red: 0.94, green: 0.75, blue: 0.47)

    @ViewBuilder private var instrumentLayout: some View {
        #if os(macOS)
        VStack(spacing: 8) {
            toneControls(columns: Self.orderedControls.count)
            controls
            retryAudio
            keyboard(layout: .full, showLabels: true, miniature: true)
                .frame(minHeight: 76, idealHeight: 112, maxHeight: 112)
            damperControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        #else
        GeometryReader { proxy in
            let wide = proxy.size.width >= 580
            let compact = proxy.size.height < 450
            VStack(spacing: compact ? 8 : 12) {
                let fitsOneRow = proxy.size.width - 32 >= fullToneRowWidth
                if compact && !fitsOneRow {
                    ScrollView(.horizontal) {
                        toneControls(columns: Self.orderedControls.count).frame(width: fullToneRowWidth)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    toneControls(columns: fitsOneRow ? Self.orderedControls.count : 5)
                }
                retryAudio
                controls
                keyboard(layout: KeyboardLayout(octave: octave, whiteCount: wide ? 14 : 7),
                         showLabels: !compact)
                    .frame(maxHeight: 460)
                    .id(KeyWindow(octave: octave, wide: wide))
                damperControl
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 8 : 16)
            .onChange(of: wide, initial: true) { _, newValue in
                releaseKeys()
                visibleNotes = newValue ? 14 : 7
                octave = min(octave, maximumOctave)
            }
        }
        #endif
    }

    var body: some View {
        instrumentLayout
            .background {
                LinearGradient(colors: [Color(white: 0.13), Color(white: 0.065)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
            .tint(brass)
            .task {
                guard playsAudio else { return }
                for parameter in SpectralParameter.allCases {
                    let percent = UserDefaults.standard.object(forKey: parameter.storageKey) as? Int
                    audio.setParameter(parameter, percent: percent ?? parameter.defaultPercent)
                }
                midi.start(receive: receiveMIDI, disconnected: disconnectMIDI)
                if phase == .active { audio.start() }
            }
            .onDisappear {
                midi.stop()
                audio.stop()
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    if playsAudio { audio.start() }
                } else {
                    releaseKeys()
                #if os(iOS)
                    if value == .background {
                        midiKeys.removeAll()
                        midiDampers.removeAll()
                        midiSoftPedals.removeAll()
                        pedal = 0
                        audio.releaseAll()
                        audio.stop()
                    }
                #endif
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)
                .receive(on: RunLoop.main)) { _ in
                guard playsAudio else { return }
            #if os(iOS)
                guard phase == .active else { return }
            #endif
                releaseKeys()
                midiKeys.removeAll()
                audio.releaseAll()
                updateDamper()
                audio.start()
            }
            .alert("Playing SDS", isPresented: $info) {
                Button("OK", role: .cancel) {}
            } message: {
            #if os(macOS)
                Text("Click or drag across the keys. Drag a knob vertically to change the spectrum. Double-click to reset it. Hold notes with Sustain or reduce the depth of sideband modulation.")
            #else
                Text("Touch several keys to play a chord. Use the arrows to shift octaves. Drag a knob vertically to change the spectrum. Sustain holds released notes, and the modulation button reduces the sidebands.")
            #endif
            }
            .environment(\.locale, language.locale)
    }

    @ViewBuilder private var retryAudio: some View {
        if audio.unavailable {
            Button("Retry audio", systemImage: "speaker.slash") { audio.start() }
                .font(.callout)
        }
    }

    private func keyboard(layout: KeyboardLayout, showLabels: Bool, miniature: Bool = false) -> some View {
        KeyboardView(layout: layout,
                     pressed: touches.union(accessibilityNotes.keys).union(midiKeys.map(\.note)),
                     showLabels: showLabels, miniature: miniature,
                     onTouches: updateTouches, onAccessibilityPlay: playAccessibleNote)
    }

    private static let orderedControls: [SpectralParameter] = [
        .timbre, .modulationIndex, .spectralTilt, .release, .phaseMotion, .flow, .coupling, .diffusion, .sidebandBalance, .volume
    ]

    private func toneControls(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(stride(from: 0, to: Self.orderedControls.count, by: columns)), id: \.self) { start in
                let end = min(start + columns, Self.orderedControls.count)
                HStack(spacing: 4) {
                    ForEach(Self.orderedControls[start..<end], id: \.self) { parameter in
                        SoundKnob(parameter: parameter, tint: brass) {
                            audio.setParameter(parameter, percent: $0)
                        }
                        .frame(width: knobWidth(for: parameter))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var fullToneRowWidth: CGFloat {
        Self.orderedControls.reduce(0) { $0 + knobWidth(for: $1) } + CGFloat(Self.orderedControls.count - 1) * 4
    }

    private func knobWidth(for parameter: SpectralParameter) -> CGFloat {
        switch parameter {
        case .sidebandBalance, .modulationIndex: 72
        case .timbre, .spectralTilt, .phaseMotion, .coupling: 62
        default: 46
        }
    }

    private var maximumOctave: Int { visibleNotes == 14 ? 6 : 7 }

    private var controls: some View {
        HStack(spacing: 8) {
            #if !os(macOS)
            HStack(spacing: 0) {
                iconButton("chevron.left", label: "Lower octave") { shift(-1) }
                    .disabled(octave == 0)
                Group {
                    if octave == 0 {
                        Text("Bass")
                    } else if octave == maximumOctave {
                        Text("Treble")
                    } else {
                        Text(verbatim: "C\(octave)")
                    }
                }
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(minWidth: 30)
                    .accessibilityLabel(Text("Octave range"))
                    .accessibilityValue(Text(verbatim: rangeDescription))
                iconButton("chevron.right", label: "Higher octave") { shift(1) }
                    .disabled(octave == maximumOctave)
            }
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            #endif

            HStack(spacing: 5) {
                Image(systemName: "speedometer")
                    .font(.footnote)
                    .foregroundStyle(brass)
                    .accessibilityHidden(true)
                Slider(value: $velocity, in: 5...100, step: 1) {
                    Text("Velocity")
                }
                .accessibilityValue(Text(verbatim: "\(Int((velocity * 1.27).rounded()))"))
            }

            pedalToggle("speaker.wave.1", label: "Reduce modulation", isOn: $softPedal)
            HStack(spacing: 0) {
                languageMenu
                iconButton("info.circle", label: "Playing SDS") { info = true }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: $language) {
                ForEach(SpectralLanguage.allCases, id: \.self) { option in
                    option.label.tag(option)
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .foregroundStyle(brass)
        .accessibilityLabel(Text("Language"))
        .help(Text("Language"))
    }

    private var damperControl: some View {
        let percent = max(pedal, Double(externalDamper) * 100 / 127).formatted(.percent.scale(1).precision(.fractionLength(0)).locale(language.locale))
        return HStack(spacing: 10) {
            iconButton("waveform.path", label: "Toggle sustain") {
                pedal = pedal == 0 ? 100 : 0
            }
            .background(pedal > 0 ? brass.opacity(0.18) : .white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12))
            .accessibilityValue(Text(percent))
            Slider(value: $pedal, in: 0...100, step: 1) {
                Text("Sustain")
            }
            .accessibilityValue(Text(percent))
            Text(percent)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .onChange(of: pedal) { _, _ in updateDamper() }
    }

    private func pedalToggle(_ symbol: String, label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .foregroundStyle(isOn.wrappedValue ? Color.black : brass)
                .background(isOn.wrappedValue ? brass : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var rangeDescription: String {
        let layout = KeyboardLayout(octave: octave, whiteCount: visibleNotes)
        return "\(noteName(layout.white.first ?? 21)) – \(noteName(layout.white.last ?? 108))"
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(brass)
        .accessibilityLabel(Text(label))
    }

    private func shift(_ direction: Int) {
        releaseKeys()
        octave = min(maximumOctave, max(0, octave + direction))
    }

    private func updateTouches(_ notes: Set<Int>) {
        for note in touches.subtracting(notes) where accessibilityNotes[note] == nil && !hasMIDIKey(note) { audio.noteOff(note) }
        for note in notes.subtracting(touches) { audio.noteOn(note, velocity: Int(velocity), soft: softPedal || !midiSoftPedals.isEmpty) }
        touches = notes
    }

    private func releaseKeys() {
        for note in touches.union(accessibilityNotes.keys) where !hasMIDIKey(note) { audio.noteOff(note) }
        touches = []
        accessibilityNotes = [:]
    }

    private var externalDamper: Int { midiDampers.values.max() ?? 0 }

    private func updateDamper() {
        if Double(externalDamper) * 100 / 127 > pedal {
            audio.midiSustain(externalDamper)
        } else {
            audio.sustain(Int(pedal))
        }
    }

    private func hasMIDIKey(_ note: Int) -> Bool { midiKeys.contains { $0.note == note } }

    private func receiveMIDI(_ source: MIDIEndpointRef, _ event: SpectralMIDI) {
        #if os(iOS)
        guard phase != .background else { return }
        #endif
        switch event {
        case let .press(channel, note, velocity):
            midiKeys.insert(MIDIKey(source: source, channel: channel, note: note))
            audio.midiNoteOn(note, velocity: velocity, soft: softPedal || !midiSoftPedals.isEmpty)
        case let .release(channel, note):
            midiKeys.remove(MIDIKey(source: source, channel: channel, note: note))
            releaseMIDINote(note)
        case let .damper(value):
            midiDampers[source] = value
            updateDamper()
        case let .soft(down):
            if down { midiSoftPedals.insert(source) } else { midiSoftPedals.remove(source) }
        case .panic:
            disconnectMIDI(source)
        }
    }

    private func disconnectMIDI(_ source: MIDIEndpointRef) {
        let released = midiKeys.filter { $0.source == source }
        midiKeys.subtract(released)
        for note in Set(released.map(\.note)) { releaseMIDINote(note) }
        midiDampers[source] = nil
        midiSoftPedals.remove(source)
        updateDamper()
    }

    private func releaseMIDINote(_ note: Int) {
        guard !hasMIDIKey(note), !touches.contains(note), accessibilityNotes[note] == nil else { return }
        audio.noteOff(note)
    }

    private func playAccessibleNote(_ note: Int) {
        let token = UUID()
        accessibilityNotes[note] = token
        audio.noteOn(note, velocity: Int(velocity), soft: softPedal || !midiSoftPedals.isEmpty)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard accessibilityNotes[note] == token else { return }
            accessibilityNotes[note] = nil
            if !touches.contains(note) && !hasMIDIKey(note) { audio.noteOff(note) }
        }
    }
}

private enum SpectralLanguage: String, CaseIterable {
    case system
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    var locale: Locale { self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue) }

    var label: Text {
        switch self {
        case .system: Text("System default")
        case .english: Text(verbatim: "English")
        case .japanese: Text(verbatim: "日本語")
        case .simplifiedChinese: Text(verbatim: "简体中文")
        }
    }

    #if os(macOS)
    var windowTitle: String {
        let bundle = Bundle.main
        if self != .system, let url = bundle.url(forResource: rawValue, withExtension: "lproj"),
           let localized = Bundle(url: url) {
            return localized.localizedString(forKey: "SDS", value: "SDS", table: nil)
        }
        return bundle.localizedString(forKey: "SDS", value: "SDS", table: nil)
    }
    #endif
}

private struct SoundKnob: View {
    @Environment(\.locale) private var locale
    let parameter: SpectralParameter
    let tint: Color
    let update: (Int) -> Void
    @AppStorage private var percent: Int
    @State private var dragStart: Int?

    init(parameter: SpectralParameter, tint: Color, update: @escaping (Int) -> Void) {
        self.parameter = parameter
        self.tint = tint
        self.update = update
        _percent = AppStorage(wrappedValue: parameter.defaultPercent, parameter.storageKey)
    }

    private var value: Int { min(100, max(0, percent)) }
    private var readout: Text {
        if parameter == .timbre {
            let index = Int((Double(value) / parameter.step).rounded())
            return Text(LocalizedStringKey(SpectralParameter.timbreNames[index]))
        }
        return Text(value.formatted(.percent.scale(1).locale(locale)))
    }

    var body: some View {
        let label = LocalizedStringKey(parameter.title)
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            knob
            readout
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            let step = max(2, Int(parameter.step))
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
        }
        .help(Text(label))
        .onChange(of: percent, initial: true) { _, value in update(value) }
    }

    private func setValue(_ requested: Int) {
        let clamped = min(100, max(0, requested))
        percent = Int((Double(clamped) / parameter.step).rounded() * parameter.step)
    }

    private var knob: some View {
        ZStack {
            ForEach(0...12, id: \.self) { tick in
                Capsule()
                    .fill(tick * 100 <= value * 12 ? tint : Color.white.opacity(0.22))
                    .frame(width: 1, height: tick.isMultiple(of: 3) ? 4 : 2)
                    .offset(y: -19.5)
                    .rotationEffect(.degrees(Double(tick) * 22.5 - 135))
            }
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.09), Color(white: 0.16)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1) }
                .frame(width: 31, height: 31)
            Capsule()
                .fill(tint)
                .frame(width: 2, height: 8)
                .offset(y: -9)
                .rotationEffect(.degrees(Double(value) * 2.7 - 135))
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { event in
            if dragStart == nil { dragStart = value }
            let start = dragStart ?? value
            if parameter.step > 1 {
                // Discrete controls advance by one detent with a short drag.
                let detents = Int((event.translation.height / 16).rounded())
                setValue(start - detents * Int(parameter.step))
            } else {
                let delta = Int((event.translation.height / 1.5).rounded())
                setValue(start - delta)
            }
        }.onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) { percent = parameter.defaultPercent }
    }
}

private struct MIDIKey: Hashable {
    let source: MIDIEndpointRef
    let channel: Int
    let note: Int
}

private struct KeyWindow: Hashable {
    let octave: Int
    let wide: Bool
}

struct SpectralView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(macOS)
        SpectralView(playsAudio: false).frame(width: 960, height: 330)
        #else
        Group {
            SpectralView(playsAudio: false)
                .previewDevice("iPhone SE (3rd generation)")
            SpectralView(playsAudio: false)
                .previewDevice("iPhone 16 Pro Max")
        }
        #endif
    }
}

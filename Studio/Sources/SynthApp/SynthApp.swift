// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/Studio/Sources/SynthApp/SynthApp.swift
// SynthApp.swift
// SDS Studio アプリケーションのエントリポイントおよびメインワークスペース画面

import SwiftUI

#if !SYNTH_AUDIO_UNIT
@main
struct SynthApp: App {
    @StateObject private var engine = SynthEngine()
    var body: some Scene {
        WindowGroup { ContentView(engine: engine) }
        #if os(macOS)
        .defaultSize(width: 1120, height: 920)
        #endif
    }
}

#endif

struct ContentView: View {
    @ObservedObject var engine: SynthEngine
    @State private var parameters = SynthParameters()
    @State private var selectedTab: WorkspaceTab = .synth
    @State private var selectedEffect: RackTab = .dimension
    @State private var programmerExpanded: Bool?
    @State private var showInfo = false
    @State private var selectedFile = 1
    @State private var bank = 1
    @State private var program = 1
    @State private var memoryStatus = ""

    private func title(_ names: [String]) -> String { instrumentText(names[0],names[1],names[2]) }
    private func binding(_ key: WritableKeyPath<SynthParameters,Float>) -> Binding<Double> {
        Binding(get:{ Double(parameters[keyPath:key]) },set:{ parameters[keyPath:key]=Float($0) })
    }
    private func binding(_ key: WritableKeyPath<SynthParameters,Bool>) -> Binding<Bool> {
        Binding(get:{ parameters[keyPath:key] },set:{ parameters[keyPath:key]=$0 })
    }
    private var controls: [PanelControl] {
        Rev3.knobs.map { item in
            PanelControl(label:item.label,title:title(item.names),value:binding(item.key),range:Double(item.range.lowerBound)...Double(item.range.upperBound),logarithmic:item.curve == 1,quantized:item.curve == 2,resetValue:Double(SynthParameters()[keyPath:item.key]))
        } + [
            PanelControl(label:"PITCH",title:instrumentText("Pitch wheel","ピッチホイール","弯音轮"),value:binding(\.pitchWheel),range:-1...1,resetValue:0),
            PanelControl(label:"MOD",title:instrumentText("Modulation wheel","モジュレーションホイール","调制轮"),value:binding(\.modWheel),range:0...1,resetValue:0)
        ]
    }
    private var switches: [PanelSwitch] {
        Rev3.switches.map { PanelSwitch(label:$0.label,title:title($0.names),value:binding($0.key)) }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.085, green: 0.098, blue: 0.118), InstrumentFinish.backdrop, Color(red: 0.035, green: 0.042, blue: 0.052)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            RadialGradient(colors: [InstrumentFinish.amber.opacity(0.055), .clear],
                           center: .top, startRadius: 20, endRadius: 680).ignoresSafeArea()
            GeometryReader { viewport in
                let width = max(1, viewport.size.width - 32)
                let compact = width < 700 || viewport.size.height < 520
                let expanded = programmerExpanded ?? false
                let short = viewport.size.height < 440
                VStack(spacing: 9) {
                    ViewThatFits(in: .horizontal) {
                        HStack { studioTitle; Spacer(minLength: 5); utilityControls }
                        VStack(alignment: .leading, spacing: 4) { studioTitle; utilityControls }
                    }
                    if !short { scopeDeck(height: compact ? 115 : 150) }

                    HStack(spacing: 6) {
                        RackTabStrip(selection: $selectedTab)
                        programmerToggle(expanded: expanded)
                        presetMenu
                    }
                    .padding(.horizontal, 8)
                    .modifier(StudioPlate())

                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 0).id("workspace-start")
                                if short { scopeDeck(height: 90).padding(3) }
                                if expanded {
                                    ProgrammerPanel(file: $selectedFile, bank: $bank, program: $program,
                                                    status: memoryStatus, recall: loadProgram, record: saveProgram,
                                                    compact: true)
                                }
                                workspace(width: width)
                            }
                        }
                        .onChange(of: programmerExpanded) {
                            scroll.scrollTo("workspace-start", anchor: .top)
                        }
                        .onChange(of: selectedTab) {
                            scroll.scrollTo("workspace-start", anchor: .top)
                        }
                        .onChange(of: selectedEffect) {
                            if selectedTab == .fx {
                                scroll.scrollTo("workspace-start", anchor: .top)
                            }
                        }
                    }
                    .modifier(StudioPlate())

                    performanceKeyboard(width: width, height: viewport.size.height)
                        .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .preferredColorScheme(.dark)
        .tint(InstrumentFinish.amber)
        .onChange(of: parameters.expression) { _, expression in
            guard !engine.isHosted, let data = try? JSONEncoder().encode(expression) else { return }
            UserDefaults.standard.set(data, forKey: "synth.expression.v1")
        }
        .onReceive(engine.$midiControlEvent) { event in
            switch event {
            case let .pitch(value): parameters.pitchWheel=value
            case let .mod(value): parameters.modWheel=value
            default: break
            }
        }
        .onReceive(engine.$hostParameters) { next in
            if engine.isHosted,let next { parameters=next }
        }
        .alert(instrumentText("Audio could not start", "音源を起動できません", "无法启动音频"),isPresented:Binding(get:{engine.startupError != nil},set:{ if !$0 {engine.startupError=nil} })) {
            Button(instrumentText("Retry","再試行","重试")) { engine.start() }
            Button(instrumentText("Close","閉じる","关闭"),role:.cancel) { engine.startupError=nil }
        } message: { Text(engine.startupError ?? "") }
        .onAppear {
            if engine.isHosted { parameters=engine.sharedParams.snapshot();engine.start();return }
            if let data=UserDefaults.standard.data(forKey:"synth.expression.v1"),
               let expression=try? JSONDecoder().decode(ExpressionParameters.self,from:data) { parameters.expression=expression }
            loadProgram(); apply(); engine.start()
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(InstrumentPreset.Family.allCases, id: \.self) { family in
                Menu(title(family.names)) {
                    ForEach(InstrumentPreset.allCases.filter { $0.family == family }) { preset in
                        Button(title(preset.names)) { loadInstrumentPreset(preset) }
                    }
                }
            }
        } label: {
            Image(systemName: "music.note.list").frame(width: 38, height: 36)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(instrumentText("Instrument presets", "楽器プリセット", "乐器预设"))
        .accessibilityLabel(instrumentText("Instrument presets", "楽器プリセット", "乐器预设"))
    }

    private func programmerToggle(expanded: Bool) -> some View {
        let label = instrumentText("Programmer", "音色管理", "音色管理")
        return Button {
            programmerExpanded = !expanded
        } label: {
            Image(systemName: expanded ? "square.stack.fill" : "square.stack")
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(HardwareButtonStyle(selected: expanded))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(expanded
            ? instrumentText("Expanded", "展開済み", "已展开")
            : instrumentText("Collapsed", "折りたたみ済み", "已折叠"))
    }

    @ViewBuilder private func workspace(width: CGFloat) -> some View {
        switch selectedTab {
        case .synth:
            StudioModules(controls: controls, switches: switches, spectral: spectralControls, width: width, changed: apply)
            expressionPanel
        case .fx:
            Menu {
                ForEach(RackTab.allCases.filter { $0 != .synth && $0 != .patch }) { effect in
                    Button { selectedEffect = effect } label: {
                        Label(effect.title, systemImage: selectedEffect == effect ? "checkmark" : effect.icon)
                    }
                }
            } label: {
                Label(selectedEffect.title, systemImage: selectedEffect.icon)
                    .frame(minHeight: 36)
            }
            .accessibilityLabel(instrumentText("Effect", "エフェクト", "效果"))
            .accessibilityValue(selectedEffect.title)
            .padding(.horizontal, 16)
            EffectsWorkspace(rack: engine.effects, tab: selectedEffect,
                             openPatch: { selectedTab = .patch })
        case .patch:
            EffectsPatchView(rack: engine.effects, editEffect: openEffect)
        }
    }

    private func performanceKeyboard(width: CGFloat, height: CGFloat) -> some View {
        let availableWidth = min(1200, max(1, width - 32))
        let keyboardHeight = min(height < 440 ? 78 : 138, max(1,height*0.22))
        let layout = PanelLayout(columns:availableWidth >= 600 ? 2 : 1,keyboardOnly:true)
        #if os(macOS)
        let keyCount = 37
        #else
        let keyCount = availableWidth < 600 && height >= width ? 15 : (availableWidth < 1000 ? 25 : 37)
        #endif
        let firstNote = keyCount == 15 ? 60 : 48
        let keyNotes = (firstNote..<(firstNote+keyCount)).filter { [0,2,4,5,7,9,11].contains($0%12) }

        return StudioKeyboard(layout: layout, keyNotes:keyNotes, controls: controls,
                                   enabled: engine.isRunning, changed: apply,
                                   noteOn: { engine.playNote($0) }, noteOff: { engine.releaseNote($0) })
            .frame(width: availableWidth, height: keyboardHeight)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .modifier(StudioPlate())
    }

    private func openEffect(_ kind: EffectKind) {
        switch kind {
        case .synth:
            selectedTab = .synth
            return
        case .dimension: selectedEffect = .dimension
        case .sky, .time: selectedEffect = .ambience
        case .pedal: selectedEffect = .pedal
        case .ring: selectedEffect = .ring
        case .studio: selectedEffect = .studio
        default: return
        }
        selectedTab = .fx
    }

    private func scopeDeck(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            StudioScope(scope: engine.outputScope, height: height)
            StudioDial(control: controls[25], changed: apply)
                .padding(.horizontal, 4)
        }
        .padding(8)
        .modifier(StudioPlate())
    }

    private var studioTitle: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.linearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.17), Color(red: 0.04, green: 0.08, blue: 0.09)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(InstrumentFinish.amber.opacity(0.45), lineWidth: 1)
                    }
                Image(systemName: "waveform.path")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(InstrumentFinish.amber)
                    .shadow(color: InstrumentFinish.amber.opacity(0.65), radius: 3)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("SDS Studio")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(InstrumentFinish.ink)
                Text("SPECTRAL DYNAMICS SYNTHESIZER")
                    .font(InstrumentFinish.legend(7.5))
                    .tracking(1.6)
                    .foregroundStyle(InstrumentFinish.muted)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var utilityControls: some View {
        HStack(spacing:6) {
            Button { showInfo.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                .help(instrumentText("Controls","操作方法","操作说明"))
                .accessibilityLabel(instrumentText("Controls","操作方法","操作说明"))
                .popover(isPresented:$showInfo) {
                    VStack(alignment:.leading,spacing:12) {
                        Text(instrumentText("Drag knobs and wheels vertically. Double-click to restore their initial setting. Hold keys to play.","ノブとホイールは上下にドラッグ。ダブルタップで初期値に戻ります。鍵盤を押して演奏します。","上下拖动旋钮和控制轮，双击恢复初始值，按住琴键演奏。"))
                        Text(engine.isHosted ? instrumentText("Audio Unit · MIDI and audio are managed by the host.","Audio Unit · MIDIと音声はホストが管理します。","Audio Unit · MIDI与音频由宿主管理。") : instrumentText(
                            "MIDI inputs: \(engine.midiSourceCount). All channels · Sustain CC64 · Mod CC1 · Pitch ±7 semitones. DAW destination: SDS Studio.",
                            "MIDI入力: \(engine.midiSourceCount)。全チャンネル・サステインCC64・Mod CC1・ピッチ±7半音。DAW入力先: SDS Studio。",
                            "MIDI输入：\(engine.midiSourceCount)。所有通道・延音CC64・调制CC1・弯音±7半音。DAW目标：SDS Studio。"))
                        if let error=engine.midiError {
                            Text(instrumentText("MIDI unavailable", "MIDIを利用できません", "MIDI不可用")+" (\(error))")
                        }
                    }.padding(20).frame(idealWidth:280)
                }
            Button { parameters.autoTuneTrigger &+= 1; apply() } label: { Image(systemName:"tuningfork").frame(width:32,height:32) }
                .help(instrumentText("Tune oscillators","オシレーターをチューニング","振荡器调音"))
                .accessibilityLabel(instrumentText("Tune","チューニング","调音"))
            Button { parameters.referenceA440.toggle(); apply() } label: { Text("A-440").frame(width:46,height:32) }
                .buttonStyle(HardwareButtonStyle(selected:parameters.referenceA440))
                .help(instrumentText("440 Hz reference tone","440 Hz 基準音","440 Hz 参考音"))
                .accessibilityValue(parameters.referenceA440 ? instrumentText("On","オン","开"):instrumentText("Off","オフ","关"))
            Button(action:togglePower) { Image(systemName:"power").frame(width:32,height:32) }
                .disabled(engine.isHosted)
                .buttonStyle(HardwareButtonStyle(selected:engine.isRunning))
                .help(instrumentText("Power","電源","电源"))
                .accessibilityLabel(instrumentText("Power","電源","电源"))
                .accessibilityValue(engine.isRunning ? instrumentText("On","オン","开"):instrumentText("Off","オフ","关"))
        }.buttonStyle(HardwareButtonStyle())
    }

    private var spectralControls: [PanelControl] {
        SpectralOscillatorParameters.knobs.map { knob in
            PanelControl(label: knob.label, title: title(knob.names), value: binding(knob.key),
                         range: 0...1, resetValue: Double(SynthParameters()[keyPath:knob.key]),
                         valueLabel: { amount in
                if knob.key == \.spectral.timbre {
                    let position = amount * 4
                    let index = Int(position.rounded())
                    if abs(position - Double(index)) < 0.12 {
                        return title(SpectralOscillatorParameters.timbres[index])
                    }
                }
                return amount.formatted(.percent.precision(.fractionLength(0)))
            })
        }
    }

    private var expressionPanel: some View {
        ExpressionPanel(parameters:$parameters.expression,changed:apply)
    }

    private func apply() {
        engine.applyParameters(parameters)
    }
    private func togglePower() {
        if engine.isRunning { engine.stop() } else { engine.start(); apply() }
    }
    private var memoryKey: String { "synth.rev3.v1.\(selectedFile).\(bank).\(program)" }
    private func loadInstrumentPreset(_ preset: InstrumentPreset) {
        engine.noteOffCurrent()
        parameters=preset.applying(to:parameters)
        apply()
        memoryStatus=title(preset.names)
    }
    private func saveProgram() {
        guard let data=try? JSONEncoder().encode(Rev3Program(parameters)) else { return }
        UserDefaults.standard.set(data,forKey:memoryKey)
        memoryStatus=instrumentText("Recorded","保存しました","已保存")
    }
    private func loadProgram() {
        guard let data=UserDefaults.standard.data(forKey:memoryKey) else {
            let legacyKey="synth.preset.\(selectedFile == 1 ? "A":"B").\((bank-1)*8+program)"
            if selectedFile <= 2,let data=UserDefaults.standard.data(forKey:legacyKey),
               let migrated=Rev3Program.migratingLegacy(data),let next=migrated.applying(to:parameters) {
                parameters=next; apply()
                memoryStatus=instrumentText("Legacy sound adapted to Rev3; original retained","旧音色をRev3用に変換しました（元データは保持）","旧音色已适配Rev3，保留原数据")
            } else { memoryStatus=instrumentText("Empty program","空きプログラム","空音色位") }
            return
        }
        guard let program=try? JSONDecoder().decode(Rev3Program.self,from:data),let next=program.applying(to:parameters) else {
            memoryStatus=instrumentText("Could not read program","音色を読み込めませんでした","无法读取音色"); return
        }
        parameters=next; apply()
        memoryStatus=instrumentText("Recalled","読み込みました","已载入")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(engine:SynthEngine()).previewDevice("iPhone SE (3rd generation)")
        ContentView(engine:SynthEngine()).previewDevice("iPhone 16 Pro Max")
    }
}

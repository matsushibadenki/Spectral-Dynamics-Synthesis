// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/Studio/Sources/SynthApp/Rev3Parameters.swift
// Rev3Parameters.swift
// シンセサイザーのボイスパラメーター、プリセット、およびノブ定義を管理するファイル

import Foundation

// Original Prophet-5 Rev3: 24 programmable potentiometers and 22 switches.
// Source: Sequential CM1000D (2/82), sections 2 and 6-7, pp. 6-5–6-6.
struct SynthParameters: Codable, Equatable {
    var expression = ExpressionParameters()
    var spectral = SpectralOscillatorSettings()
    var polyModFilterEnv: Float = 0
    var polyModOscB: Float = 0
    var lfoRateHz: Float = 3
    var wheelSourceMix: Float = 0
    var oscAFrequency: Float = 24
    var oscAPulseWidth: Float = 0.5
    var oscBFrequency: Float = 24
    var oscBFineCents: Float = 0
    var oscBPulseWidth: Float = 0.5
    var oscALevel: Float = 0.8
    var oscBLevel: Float = 0
    var noiseLevel: Float = 0
    var cutoffNorm: Float = 0.80
    var resonance: Float = 0.18
    var filterEnvAmount: Float = 0.22
    var envAAttack: Float = 0.02
    var envADecay: Float = 0.2
    var envASustain: Float = 0.75
    var envARelease: Float = 0.3
    var envBAttack: Float = 0.01
    var envBDecay: Float = 0.18
    var envBSustain: Float = 0.8
    var envBRelease: Float = 0.3
    var glideTime: Float = 0
    var masterTuneSemitones: Float = 0
    var masterVolume: Float = 0.8
    var polyModToFreqA: Bool = false
    var polyModToPWA: Bool = false
    var polyModToFilter: Bool = false
    var lfoSaw: Bool = false
    var lfoTriangle: Bool = true
    var lfoSquare: Bool = false
    var lfoToOscA: Bool = true
    var lfoToOscB: Bool = false
    var lfoToPWA: Bool = false
    var lfoToPWB: Bool = false
    var lfoToFilter: Bool = false
    var oscASaw: Bool = true
    var oscAPulse: Bool = false
    var oscSync: Bool = false
    var oscBSaw: Bool = true
    var oscBTriangle: Bool = false
    var oscBPulse: Bool = false
    var oscBLowFreqMode: Bool = false
    var oscBKeyboardTrack: Bool = true
    var filterKeyboardTrack: Bool = true
    var releaseEnabled: Bool = true
    var unisonMode: Bool = false
    // Performance controls and commands are not part of a stored voice program.
    var modWheel: Float = 0
    var pitchWheel: Float = 0
    var referenceA440 = false
    var autoTuneTrigger: UInt32 = 0
}

struct Rev3Knob {
    let id: String
    let label: String
    let names: [String]
    let key: WritableKeyPath<SynthParameters, Float>
    let range: ClosedRange<Float>
    let curve: Int // 0 linear; 1 logarithmic; 2 quantized semitones
    var programmable: Bool { id != "masterTuneSemitones" && id != "masterVolume" }
    func clamped(_ value: Float) -> Float {
        let value = value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : range.lowerBound
        return curve == 2 ? value.rounded() : value
    }
    func normalized(_ p: SynthParameters) -> Double {
        let v=clamped(p[keyPath:key])
        return Double(curve == 1 ? log(v/range.lowerBound)/log(range.upperBound/range.lowerBound) : (v-range.lowerBound)/(range.upperBound-range.lowerBound))
    }
    func value(_ n: Double) -> Float {
        let v=Float(min(1,max(0,n)))
        return clamped(curve == 1 ? range.lowerBound*pow(range.upperBound/range.lowerBound,v) : range.lowerBound+v*(range.upperBound-range.lowerBound))
    }
}
struct Rev3Switch {
    let id: String
    let label: String
    let names: [String]
    let key: WritableKeyPath<SynthParameters, Bool>
}
struct Rev3Section {
    let title: String
    let knobs: [Int]
    let switches: [Int]
}
enum Rev3 {
    static let knobs: [Rev3Knob] = [
        .init(id:"polyModFilterEnv",label:"FILTER ENV",names:["Poly-Mod filter envelope","Poly-Mod フィルターEG","Poly-Mod 滤波包络"],key:\.polyModFilterEnv,range:0...1,curve:0),
        .init(id:"polyModOscB",label:"OSC B",names:["Poly-Mod oscillator B","Poly-Mod OSC B","Poly-Mod 振荡器B"],key:\.polyModOscB,range:0...1,curve:0),
        .init(id:"lfoRateHz",label:"FREQUENCY",names:["LFO frequency","LFO 周波数","LFO 频率"],key:\.lfoRateHz,range:0.04...20,curve:1),
        .init(id:"wheelSourceMix",label:"SOURCE MIX",names:["Wheel-Mod LFO / noise mix","Wheel-Mod LFO／ノイズ比率","Wheel-Mod LFO／噪声混合"],key:\.wheelSourceMix,range:0...1,curve:0),
        .init(id:"oscAFrequency",label:"FREQUENCY",names:["Oscillator A frequency","OSC A 周波数","振荡器A频率"],key:\.oscAFrequency,range:0...48,curve:2),
        .init(id:"oscAPulseWidth",label:"PULSE WIDTH",names:["Oscillator A pulse width","OSC A パルス幅","振荡器A脉宽"],key:\.oscAPulseWidth,range:0.01...0.99,curve:0),
        .init(id:"oscBFrequency",label:"FREQUENCY",names:["Oscillator B frequency","OSC B 周波数","振荡器B频率"],key:\.oscBFrequency,range:0...48,curve:2),
        .init(id:"oscBFineCents",label:"FINE",names:["Oscillator B fine tuning","OSC B 微調整","振荡器B微调"],key:\.oscBFineCents,range:0...100,curve:0),
        .init(id:"oscBPulseWidth",label:"PULSE WIDTH",names:["Oscillator B pulse width","OSC B パルス幅","振荡器B脉宽"],key:\.oscBPulseWidth,range:0.01...0.99,curve:0),
        .init(id:"oscALevel",label:"OSC A",names:["Oscillator A level","OSC A レベル","振荡器A电平"],key:\.oscALevel,range:0...1,curve:0),
        .init(id:"oscBLevel",label:"OSC B",names:["Oscillator B level","OSC B レベル","振荡器B电平"],key:\.oscBLevel,range:0...1,curve:0),
        .init(id:"noiseLevel",label:"NOISE",names:["White noise level","ホワイトノイズ","白噪声电平"],key:\.noiseLevel,range:0...1,curve:0),
        .init(id:"cutoffNorm",label:"CUTOFF",names:["Filter cutoff","フィルター カットオフ","滤波器截止频率"],key:\.cutoffNorm,range:0...1,curve:0),
        .init(id:"resonance",label:"RESONANCE",names:["Filter resonance","フィルター レゾナンス","滤波器共振"],key:\.resonance,range:0...1,curve:0),
        .init(id:"filterEnvAmount",label:"ENV AMOUNT",names:["Filter envelope amount","フィルターEG量","滤波包络深度"],key:\.filterEnvAmount,range:0...1,curve:0),
        .init(id:"envAAttack",label:"ATTACK",names:["Filter attack","フィルター アタック","滤波器起音"],key:\.envAAttack,range:0.001...30,curve:1),
        .init(id:"envADecay",label:"DECAY",names:["Filter decay","フィルター ディケイ","滤波器衰减"],key:\.envADecay,range:0.001...30,curve:1),
        .init(id:"envASustain",label:"SUSTAIN",names:["Filter sustain","フィルター サステイン","滤波器持续"],key:\.envASustain,range:0...1,curve:0),
        .init(id:"envARelease",label:"RELEASE",names:["Filter release","フィルター リリース","滤波器释音"],key:\.envARelease,range:0.001...30,curve:1),
        .init(id:"envBAttack",label:"ATTACK",names:["Amplifier attack","音量 アタック","音量起音"],key:\.envBAttack,range:0.001...30,curve:1),
        .init(id:"envBDecay",label:"DECAY",names:["Amplifier decay","音量 ディケイ","音量衰减"],key:\.envBDecay,range:0.001...30,curve:1),
        .init(id:"envBSustain",label:"SUSTAIN",names:["Amplifier sustain","音量 サステイン","音量持续"],key:\.envBSustain,range:0...1,curve:0),
        .init(id:"envBRelease",label:"RELEASE",names:["Amplifier release","音量 リリース","音量释音"],key:\.envBRelease,range:0.001...30,curve:1),
        .init(id:"glideTime",label:"GLIDE",names:["Unison glide","ユニゾン グライド","齐奏滑音"],key:\.glideTime,range:0...5,curve:0),
        .init(id:"masterTuneSemitones",label:"MASTER TUNE",names:["Master tune","マスターチューン","总调音"],key:\.masterTuneSemitones,range:-1...1,curve:0),
        .init(id:"masterVolume",label:"VOLUME",names:["Master volume","マスター音量","主音量"],key:\.masterVolume,range:0...1,curve:0),
    ]
    static let switches: [Rev3Switch] = [
        .init(id:"polyModToFreqA",label:"FREQ A",names:["Poly-Mod to oscillator A frequency","Poly-Mod → OSC A 周波数","Poly-Mod → A频率"],key:\.polyModToFreqA),
        .init(id:"polyModToPWA",label:"PW A",names:["Poly-Mod to oscillator A pulse width","Poly-Mod → OSC A パルス幅","Poly-Mod → A脉宽"],key:\.polyModToPWA),
        .init(id:"polyModToFilter",label:"FILTER",names:["Poly-Mod to filter","Poly-Mod → フィルター","Poly-Mod → 滤波器"],key:\.polyModToFilter),
        .init(id:"lfoSaw",label:"SAW",names:["LFO sawtooth","LFO ノコギリ波","LFO 锯齿波"],key:\.lfoSaw),
        .init(id:"lfoTriangle",label:"TRIANGLE",names:["LFO triangle","LFO 三角波","LFO 三角波"],key:\.lfoTriangle),
        .init(id:"lfoSquare",label:"SQUARE",names:["LFO square","LFO 矩形波","LFO 方波"],key:\.lfoSquare),
        .init(id:"lfoToOscA",label:"FREQ A",names:["Wheel-Mod to oscillator A frequency","Wheel-Mod → OSC A 周波数","Wheel-Mod → A频率"],key:\.lfoToOscA),
        .init(id:"lfoToOscB",label:"FREQ B",names:["Wheel-Mod to oscillator B frequency","Wheel-Mod → OSC B 周波数","Wheel-Mod → B频率"],key:\.lfoToOscB),
        .init(id:"lfoToPWA",label:"PW A",names:["Wheel-Mod to oscillator A pulse width","Wheel-Mod → OSC A パルス幅","Wheel-Mod → A脉宽"],key:\.lfoToPWA),
        .init(id:"lfoToPWB",label:"PW B",names:["Wheel-Mod to oscillator B pulse width","Wheel-Mod → OSC B パルス幅","Wheel-Mod → B脉宽"],key:\.lfoToPWB),
        .init(id:"lfoToFilter",label:"FILTER",names:["Wheel-Mod to filter","Wheel-Mod → フィルター","Wheel-Mod → 滤波器"],key:\.lfoToFilter),
        .init(id:"oscASaw",label:"SAW",names:["Oscillator A sawtooth","OSC A ノコギリ波","振荡器A锯齿波"],key:\.oscASaw),
        .init(id:"oscAPulse",label:"PULSE",names:["Oscillator A pulse","OSC A パルス波","振荡器A脉冲波"],key:\.oscAPulse),
        .init(id:"oscSync",label:"SYNC",names:["Oscillator sync B to A","OSC 同期 B → A","振荡器同步 B → A"],key:\.oscSync),
        .init(id:"oscBSaw",label:"SAW",names:["Oscillator B sawtooth","OSC B ノコギリ波","振荡器B锯齿波"],key:\.oscBSaw),
        .init(id:"oscBTriangle",label:"TRIANGLE",names:["Oscillator B triangle","OSC B 三角波","振荡器B三角波"],key:\.oscBTriangle),
        .init(id:"oscBPulse",label:"PULSE",names:["Oscillator B pulse","OSC B パルス波","振荡器B脉冲波"],key:\.oscBPulse),
        .init(id:"oscBLowFreqMode",label:"LO FREQ",names:["Oscillator B low frequency","OSC B 低周波モード","振荡器B低频模式"],key:\.oscBLowFreqMode),
        .init(id:"oscBKeyboardTrack",label:"KEYBOARD",names:["Oscillator B keyboard tracking","OSC B キーボード追従","振荡器B键盘跟踪"],key:\.oscBKeyboardTrack),
        .init(id:"filterKeyboardTrack",label:"KEYBOARD",names:["Filter keyboard tracking","フィルター キーボード追従","滤波器键盘跟踪"],key:\.filterKeyboardTrack),
        .init(id:"releaseEnabled",label:"RELEASE",names:["Enable envelope release","EGリリース有効","启用包络释音"],key:\.releaseEnabled),
        .init(id:"unisonMode",label:"UNISON",names:["Unison lowest-note priority","ユニゾン 最低音優先","齐奏最低音优先"],key:\.unisonMode),
    ]
    static let sections: [Rev3Section] = [
        .init(title:"POLY-MOD",knobs:[0,1],switches:[0,1,2]),
        .init(title:"LFO",knobs:[2],switches:[3,4,5]),
        .init(title:"WHEEL-MOD",knobs:[3],switches:[6,7,8,9,10]),
        .init(title:"OSCILLATOR A",knobs:[4,5],switches:[11,12,13]),
        .init(title:"OSCILLATOR B",knobs:[6,7,8],switches:[14,15,16,17,18]),
        .init(title:"MIXER",knobs:[9,10,11],switches:[]),
        .init(title:"FILTER",knobs:[12,13,14],switches:[19]),
        .init(title:"FILTER ENVELOPE",knobs:[15,16,17,18],switches:[]),
        .init(title:"AMPLIFIER",knobs:[19,20,21,22],switches:[]),
        .init(title:"PERFORMANCE",knobs:[23,24,25],switches:[20,21])
    ]
}

// A program contains exactly the 46 voice settings. Wheels, volume, tuning and
// A-440 remain live when recalling it, just as on the original instrument.
struct Rev3Program: Codable, Equatable {
    let version: Int
    var pots: [String: Float]
    var switches: [String: Bool]
    var spectral: SpectralOscillatorSettings?
    init(_ p: SynthParameters) {
        version=1
        spectral=p.spectral
        pots=Dictionary(uniqueKeysWithValues:Rev3.knobs.filter(\.programmable).map { ($0.id,$0.clamped(p[keyPath:$0.key])) })
        switches=Dictionary(uniqueKeysWithValues:Rev3.switches.map { ($0.id,p[keyPath:$0.key]) })
    }
    func applying(to current: SynthParameters) -> SynthParameters? {
        guard version == 1, Set(pots.keys) == Set(Rev3.knobs.filter(\.programmable).map(\.id)),
              Set(switches.keys) == Set(Rev3.switches.map(\.id)), pots.values.allSatisfy(\.isFinite) else { return nil }
        var result=current
        result.spectral=spectral ?? SpectralOscillatorSettings(blend: 0)
        for item in SpectralOscillatorParameters.knobs {
            result[keyPath:item.key]=item.clamped(result[keyPath:item.key])
        }
        for item in Rev3.knobs where item.programmable { result[keyPath:item.key]=item.clamped(pots[item.id]!) }
        for item in Rev3.switches { result[keyPath:item.key]=switches[item.id]! }
        return result
    }
}

extension Rev3Program {
    // Read-only migration. The original A/B data remains untouched until the user
    // records a separate Rev3 program. Unsupported voices cannot be lossless.
    static func migratingLegacy(_ data: Data) -> Rev3Program? {
        guard let old=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              old["cutoff"] is NSNumber,old["oscAWave"] is NSNumber else { return nil }
        var p=SynthParameters()
        p.spectral.blend=0
        let names=["cutoffNorm":"cutoff","oscBFineCents":"oscBFine","oscAPulseWidth":"pwmA","oscBPulseWidth":"pwmB","envAAttack":"envAA","envADecay":"envAD","envASustain":"envAS","envARelease":"envAR","envBAttack":"envBA","envBDecay":"envBD","envBSustain":"envBS","envBRelease":"envBR","lfoRateHz":"lfoRate"]
        for item in Rev3.knobs where item.programmable {
            if let v=old[names[item.id] ?? item.id] as? NSNumber { p[keyPath:item.key]=item.clamped(v.floatValue) }
        }
        for item in Rev3.switches {
            if let v=old[item.id] as? Bool { p[keyPath:item.key]=v }
        }
        let a=(old["oscAWave"] as? Int) ?? 0,b=(old["oscBWave"] as? Int) ?? 0,lfo=(old["lfoWave"] as? Int) ?? 0
        p.oscASaw=a != 2; p.oscAPulse=a == 2
        p.oscBSaw=b == 0; p.oscBTriangle=b == 1; p.oscBPulse=b == 2
        p.lfoTriangle=lfo == 0; p.lfoSaw=lfo == 1; p.lfoSquare=lfo == 2
        p.wheelSourceMix=lfo == 3 ? 1:0
        if (old["glideOn"] as? Bool) == false { p.glideTime=0 }
        return Rev3Program(p)
    }
}

// Synthesized instrument references for judging attack, decay and sustained level.
// Separate from user memory slots; no factory program data is installed or replaced.
enum InstrumentPreset: String, CaseIterable, Identifiable {
    case piano, violin, viola, cello, doubleBass, pizzicato, harp
    case piccolo, flute, oboe, clarinet, bassoon
    case trumpet, frenchHorn, trombone, tuba
    case timpani, snare, triangle, glockenspiel

    enum Family: CaseIterable {
        case strings, woodwinds, brass, percussion, keys

        var names: [String] {
            switch self {
            case .strings: ["Strings", "弦楽器", "弦乐"]
            case .woodwinds: ["Woodwinds", "木管楽器", "木管"]
            case .brass: ["Brass", "金管楽器", "铜管"]
            case .percussion: ["Percussion", "打楽器", "打击乐"]
            case .keys: ["Keys", "鍵盤楽器", "键盘乐器"]
            }
        }
    }

    var family: Family {
        switch self {
        case .violin, .viola, .cello, .doubleBass, .pizzicato, .harp: .strings
        case .piccolo, .flute, .oboe, .clarinet, .bassoon: .woodwinds
        case .trumpet, .frenchHorn, .trombone, .tuba: .brass
        case .timpani, .snare, .triangle, .glockenspiel: .percussion
        case .piano: .keys
        }
    }
    var id: String { rawValue }
    var names: [String] {
        switch self {
        case .piano: return ["Piano", "ピアノ", "钢琴"]
        case .violin: return ["Violin", "バイオリン", "小提琴"]
        case .viola: return ["Viola", "ヴィオラ", "中提琴"]
        case .cello: return ["Cello", "チェロ", "大提琴"]
        case .doubleBass: return ["Double bass", "コントラバス", "低音提琴"]
        case .pizzicato: return ["Pizzicato strings", "ピチカート弦", "拨弦弦乐"]
        case .harp: return ["Harp", "ハープ", "竖琴"]
        case .piccolo: return ["Piccolo", "ピッコロ", "短笛"]
        case .flute: return ["Flute", "フルート", "长笛"]
        case .oboe: return ["Oboe", "オーボエ", "双簧管"]
        case .clarinet: return ["Clarinet", "クラリネット", "单簧管"]
        case .bassoon: return ["Bassoon", "ファゴット", "巴松管"]
        case .trumpet: return ["Trumpet", "トランペット", "小号"]
        case .frenchHorn: return ["French horn", "ホルン", "圆号"]
        case .trombone: return ["Trombone", "トロンボーン", "长号"]
        case .tuba: return ["Tuba", "チューバ", "大号"]
        case .timpani: return ["Timpani", "ティンパニ", "定音鼓"]
        case .snare: return ["Orchestral snare", "オーケストラ・スネア", "管弦乐小军鼓"]
        case .triangle: return ["Triangle", "トライアングル", "三角铁"]
        case .glockenspiel: return ["Glockenspiel", "グロッケンシュピール", "钟琴"]
        }
    }
    var program: Rev3Program {
        var p=SynthParameters()
        p.spectral.blend=0
        p.oscBFineCents=0; p.noiseLevel=0; p.unisonMode=false
        p.lfoToOscA=false; p.lfoToOscB=false
        switch self {
        case .piano:
            // Triangle body and a narrow upper-octave pulse give a rounded body
            // with a bright hammer-like transient. Both envelopes decay to zero.
            p.oscASaw=false; p.oscAPulse=true; p.oscAPulseWidth=0.18
            p.oscAFrequency=36; p.oscALevel=0.38
            p.oscBSaw=false; p.oscBTriangle=true; p.oscBLevel=0.65
            p.cutoffNorm=0.48; p.resonance=0.10; p.filterEnvAmount=0.28
            p.envAAttack=0.001; p.envADecay=0.65; p.envASustain=0; p.envARelease=0.18
            p.envBAttack=0.001; p.envBDecay=2.4; p.envBSustain=0; p.envBRelease=0.18
        case .violin:
            // Bow-like swell, saw harmonics and a quiet triangle body. Vibrato
            // is optional on the mod wheel, routed equally to both oscillators.
            p.oscALevel=0.55; p.oscBSaw=false; p.oscBTriangle=true; p.oscBLevel=0.28
            p.cutoffNorm=0.57; p.resonance=0.12; p.filterEnvAmount=0.08
            p.envAAttack=0.09; p.envADecay=0.35; p.envASustain=0.75; p.envARelease=0.25
            p.envBAttack=0.18; p.envBDecay=0.3; p.envBSustain=0.82; p.envBRelease=0.22
            p.lfoRateHz=5; p.lfoToOscA=true; p.lfoToOscB=true
        default:
            orchestralVoice(&p)
        }
        return Rev3Program(p)
    }
    private func orchestralVoice(_ p: inout SynthParameters) {
        p.spectral.blend = 1
        p.spectral.modulation = 0.16
        p.spectral.diffusion = 0.08
        p.spectral.coupling = 0.10
        p.spectral.motion = 0.10
        p.oscALevel = 0.8
        p.oscBSaw = false
        p.oscBTriangle = true
        p.oscBLevel = 0.18
        p.resonance = 0.08
        p.filterEnvAmount = 0.16
        p.envASustain = 0.2
        p.envAAttack = 0.025
        p.envADecay = 0.18
        p.envBDecay = 0.22
        p.envBSustain = 0.78
        p.lfoToOscA = true
        p.lfoRateHz = 5.1

        switch self {
        case .viola:
            p.spectral.timbre = 0.47; p.spectral.tilt = 0.44
            p.cutoffNorm = 0.49; p.envBAttack = 0.10; p.envBRelease = 0.35
            p.oscBFineCents = 4
        case .cello:
            p.spectral.timbre = 0.43; p.spectral.tilt = 0.36
            p.cutoffNorm = 0.44; p.envBAttack = 0.13; p.envBRelease = 0.43
            p.oscBFrequency = 12; p.oscBLevel = 0.30
        case .doubleBass:
            p.spectral.timbre = 0.33; p.spectral.tilt = 0.23
            p.cutoffNorm = 0.34; p.envBAttack = 0.16; p.envBRelease = 0.42
            p.oscAFrequency = 12; p.oscBFrequency = 12; p.oscBLevel = 0.40
        case .pizzicato, .harp:
            p.spectral.timbre = self == .harp ? 0.31 : 0.52
            p.cutoffNorm = self == .harp ? 0.56 : 0.47
            p.envBAttack = 0.002; p.envBSustain = 0
            p.envBDecay = self == .harp ? 1.7 : 0.46
            p.envBRelease = self == .harp ? 0.75 : 0.16
            p.envAAttack = 0.002; p.envASustain = 0; p.envADecay = 0.13
            p.oscBFineCents = self == .harp ? 2 : 8
        case .piccolo, .flute:
            p.spectral.timbre = self == .piccolo ? 0.08 : 0.03
            p.cutoffNorm = self == .piccolo ? 0.71 : 0.52
            p.oscAFrequency = self == .piccolo ? 36 : 24
            p.oscBFrequency = p.oscAFrequency
            p.noiseLevel = self == .piccolo ? 0.018 : 0.03
            p.envBAttack = self == .piccolo ? 0.035 : 0.07
            p.envBRelease = 0.16; p.envBSustain = 0.91
        case .oboe, .clarinet, .bassoon:
            p.spectral.timbre = self == .clarinet ? 0.25 : (self == .oboe ? 0.52 : 0.38)
            p.spectral.tilt = self == .oboe ? 0.86 : 0.45
            p.cutoffNorm = self == .oboe ? 0.59 : (self == .clarinet ? 0.43 : 0.39)
            p.resonance = self == .oboe ? 0.31 : 0.18
            p.oscBLevel = self == .clarinet ? 0.03 : 0.18
            p.oscAFrequency = self == .bassoon ? 12 : 24
            p.oscBFrequency = p.oscAFrequency
            p.envBAttack = 0.045; p.envBRelease = 0.15
        case .trumpet, .frenchHorn, .trombone, .tuba:
            p.spectral.timbre = self == .frenchHorn ? 0.39 : 0.51
            p.spectral.tilt = self == .trumpet ? 0.94 : 0.63
            p.cutoffNorm = self == .trumpet ? 0.67 : (self == .tuba ? 0.35 : 0.49)
            p.oscAFrequency = self == .trombone || self == .tuba ? 12 : 24
            p.oscBFrequency = p.oscAFrequency
            p.oscBSaw = self == .trumpet || self == .trombone
            p.oscBTriangle = !p.oscBSaw
            p.oscBLevel = self == .tuba ? 0.35 : 0.20
            p.filterEnvAmount = self == .trumpet ? 0.32 : 0.22
            p.envAAttack = self == .frenchHorn ? 0.14 : 0.028
            p.envBAttack = self == .frenchHorn ? 0.18 : (self == .tuba ? 0.10 : 0.055)
            p.envBRelease = 0.23
        case .timpani, .snare, .triangle, .glockenspiel:
            p.envAAttack = 0.001; p.envBAttack = 0.001
            p.envASustain = 0; p.envBSustain = 0
            p.envADecay = 0.12; p.envBRelease = 0.22
            p.lfoToOscA = false
            switch self {
            case .timpani:
                p.spectral.timbre = 0.10; p.spectral.modulation = 0.37
                p.oscAFrequency = 12; p.oscBFrequency = 12
                p.cutoffNorm = 0.37; p.resonance = 0.23
                p.noiseLevel = 0.045; p.envBDecay = 1.25
            case .snare:
                p.noiseLevel = 0.58; p.oscALevel = 0.18; p.oscBLevel = 0.05
                p.spectral.timbre = 0.19; p.cutoffNorm = 0.70
                p.envBDecay = 0.21; p.envBRelease = 0.08
            case .triangle:
                p.spectral.timbre = 0.75; p.spectral.modulation = 0.92; p.spectral.balance = 0.66
                p.oscAFrequency = 48; p.oscBLevel = 0
                p.cutoffNorm = 0.84; p.envBDecay = 2.7; p.envBRelease = 0.65
            default:
                p.spectral.timbre = 0.72; p.spectral.modulation = 0.38
                p.oscAFrequency = 36; p.oscBFrequency = 36; p.oscBLevel = 0.32
                p.cutoffNorm = 0.76; p.envBDecay = 1.7; p.envBRelease = 0.37
            }
        case .piano, .violin:
            break
        }
    }

    func applying(to current: SynthParameters) -> SynthParameters {
        var result=program.applying(to:current)!
        // Neutral performance offsets make these reference sounds repeatable.
        // Keep master volume/tuning and the Tune command counter owned by the player.
        result.modWheel=0; result.pitchWheel=0; result.referenceA440=false
        return result
    }
}

// Separate from the original 46-setting program schema.
struct ExpressionParameters: Codable, Equatable {
    var voiceLimit: Int { enabled ? 8 : 5 }
    var enabled = false
    var sub: Float = 0.25
    var motion: Float = 0.2
    var rate: Float = 0.4
    var pan: Float = 0.3
    var ladder: Float = 0
    var drive: Float = 0
    var feedback: Float = 0
    var slope: Float = 1
    var oscillatorColor: Float = 0
    var mixerDrive: Float = 0
    init(enabled: Bool = false) { self.enabled=enabled }
    private enum CodingKeys: String, CodingKey { case enabled, sub, motion, rate, pan, ladder, drive, feedback, slope, oscillatorColor, mixerDrive }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? false
        sub=try c.decodeIfPresent(Float.self,forKey:.sub) ?? 0.25
        motion=try c.decodeIfPresent(Float.self,forKey:.motion) ?? 0.2
        rate=try c.decodeIfPresent(Float.self,forKey:.rate) ?? 0.4
        pan=try c.decodeIfPresent(Float.self,forKey:.pan) ?? 0.3
        ladder=try c.decodeIfPresent(Float.self,forKey:.ladder) ?? 0
        drive=try c.decodeIfPresent(Float.self,forKey:.drive) ?? 0
        feedback=try c.decodeIfPresent(Float.self,forKey:.feedback) ?? 0
        slope=try c.decodeIfPresent(Float.self,forKey:.slope) ?? 1
        oscillatorColor=try c.decodeIfPresent(Float.self,forKey:.oscillatorColor) ?? 0
        mixerDrive=try c.decodeIfPresent(Float.self,forKey:.mixerDrive) ?? 0
    }
    var colorAmounts: SIMD4<Float> {
        enabled ? SIMD4(Self.unit(ladder),Self.unit(drive),Self.unit(feedback),Self.unit(slope)) : SIMD4(0,0,0,Self.unit(slope))
    }
    static func unit(_ value: Float) -> Float { value.isFinite ? min(1,max(0,value)) : 0 }
    var amounts: SIMD3<Float> {
        enabled ? SIMD3(Self.unit(sub),Self.unit(motion),Self.unit(pan)) : .zero
    }
    var rateHz: Float { rate.isFinite ? min(8,max(0.05,rate)) : 0.4 }
}

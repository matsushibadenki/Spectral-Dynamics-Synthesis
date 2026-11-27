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

import CoreMIDI

/// MIDI 1.0 messages used by the standalone input and the Audio Unit.
enum SpectralMIDI {
    case press(channel: Int, note: Int, velocity: Int)
    case release(channel: Int, note: Int)
    case damper(Int)
    case soft(Bool)
    case panic

    init?(ump: MIDIUniversalMessage) {
        guard ump.type.rawValue == 2 else { return nil }
        let voice = ump.channelVoice1
        let status = UInt8(voice.status.rawValue) << 4 | voice.channel
        if status & 0xF0 == 0xB0 {
            self.init(status: status, first: voice.controlChange.index, second: voice.controlChange.data)
        } else {
            guard status & 0xF0 == 0x80 || status & 0xF0 == 0x90 else { return nil }
            self.init(status: status, first: voice.note.number, second: voice.note.velocity)
        }
    }

    init?(status: UInt8, first: UInt8, second: UInt8) {
        let channel = Int(status & 0x0F)
        let note = Int(first)
        switch status & 0xF0 {
        case 0x80, 0x90:
            if status & 0xF0 == 0x90 && second != 0 {
                guard (21...108).contains(note) else { return nil }
                self = .press(channel: channel, note: note, velocity: Int(second))
                return
            }
            guard (21...108).contains(note) else { return nil }
            self = .release(channel: channel, note: note)
        case 0xB0:
            switch first {
            case 64: self = .damper(Int(second))
            case 67: self = .soft(second >= 64)
            case 120, 123: self = .panic
            default: return nil
            }
        default:
            return nil
        }
    }
}

import AVFoundation
import OSLog
import Synchronization

/// Single producer (UI), single consumer (audio callback).
private final class NoteQueue: @unchecked Sendable {
    // The two low 7-bit fields hold the MIDI note and velocity percentage.
    private static let softFlag = 1 << 14
    private static let midiFlag = 1 << 15
    private let capacity = 256
    private let commands = UnsafeMutablePointer<Int>.allocate(capacity: 256)
    private let read = Atomic<Int>(0)
    private let write = Atomic<Int>(0)
    private let reset = Atomic<Bool>(false)

    deinit { commands.deallocate() }

    func push(_ command: Int) {
        let tail = write.load(ordering: .relaxed)
        let next = (tail + 1) % capacity
        if next == read.load(ordering: .acquiring) {
            reset.store(true, ordering: .releasing)
            return
        }
        commands[tail] = command
        write.store(next, ordering: .releasing)
    }

    func noteOn(_ note: Int, velocity: Int, soft: Bool, midi: Bool = false) {
        push(note + velocity * 128 + (soft ? Self.softFlag : 0) + (midi ? Self.midiFlag : 0))
    }

    func drain(into model: SpectralModel) {
        var head = read.load(ordering: .relaxed)
        let tail = write.load(ordering: .acquiring)
        if reset.exchange(false, ordering: .acquiringAndReleasing) {
            read.store(tail, ordering: .releasing)
            model.releaseAll()
            return
        }
        while head != tail {
            let command = commands[head]
            switch command {
            case -1: model.releaseAll()
            case -102 ... -2: model.sustain(Float(-command - 2) / 100)
            case -230 ... -103: model.sustain(Float(-command - 103) / 127)
            case 0..<128: model.noteOff(command)
            default:
                let velocity = (command / 128) % 128
                let maximum: Float = command & Self.midiFlag == 0 ? 100 : 127
                model.noteOn(command % 128, velocity: Float(velocity) / maximum, soft: command & Self.softFlag != 0)
            }
            head = (head + 1) % capacity
        }
        read.store(head, ordering: .releasing)
    }
}

@MainActor
final class SpectralAudio: ObservableObject {
    @Published private(set) var unavailable = false
    private let worker = AudioEngineWorker()
    private var queue = NoteQueue()
    private var generation = 0
    private var starting = false
    private var pedalCommand = -2

    func start() {
        guard !starting else { return }
        starting = true
        let request = generation
        worker.start { [weak self] result in
            guard let self, self.generation == request else { return }
            self.starting = false
            self.unavailable = result == nil
            if let result, self.queue !== result {
                self.queue = result
                result.push(self.pedalCommand)
            }
        }
    }

    func stop() {
        generation += 1
        starting = false
        queue = NoteQueue()
        worker.stop()
    }

    func noteOn(_ note: Int, velocity: Int, soft: Bool) { queue.noteOn(note, velocity: velocity, soft: soft) }
    func midiNoteOn(_ note: Int, velocity: Int, soft: Bool) { queue.noteOn(note, velocity: velocity, soft: soft, midi: true) }
    func noteOff(_ note: Int) { queue.push(note) }
    func sustain(_ percent: Int) {
        pedalCommand = -2 - min(100, max(0, percent))
        queue.push(pedalCommand)
    }

    func midiSustain(_ value: Int) {
        pedalCommand = -103 - min(127, max(0, value))
        queue.push(pedalCommand)
    }

    func releaseAll() {
        pedalCommand = -2
        queue.push(-1)
    }
    func setParameter(_ parameter: SpectralParameter, percent: Int) {
        worker.parameters.set(parameter, Float(percent))
    }
}

/// Serializes engine and session lifecycle work away from the UI and render threads.
private final class AudioEngineWorker: @unchecked Sendable {
    private enum StartupError: Error {
        case invalidSourceFormat
    }

    private let logger = Logger(subsystem: "com.local.SpectralDynamicsSynthesis", category: "Audio")
    private let lifecycle = DispatchQueue(label: "com.local.SpectralDynamicsSynthesis.audio", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var notes: NoteQueue?
    let parameters = SpectralParameters()

    func start(completion: @escaping @MainActor @Sendable (NoteQueue?) -> Void) {
        lifecycle.async {
            do {
                let notes = try self.startEngine()
                DispatchQueue.main.async { completion(notes) }
            } catch {
                let error = error as NSError
                self.logger.error("SDS audio start failed (\(error.domain, privacy: .public) \(error.code)): \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func stop() {
        lifecycle.async {
            self.engine?.stop()
            self.engine = nil
            self.notes = nil
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    private func startEngine() throws -> NoteQueue {
        if engine?.isRunning == true, let notes { return notes }
        engine = nil
        notes = nil
        let newEngine = AVAudioEngine()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        let deviceRate = session.sampleRate
        #else
        let deviceRate = newEngine.outputNode.outputFormat(forBus: 0).sampleRate
        #endif
        guard let format = AVAudioFormat(standardFormatWithSampleRate: min(48_000, max(44_100, deviceRate)), channels: 2) else {
            throw StartupError.invalidSourceFormat
        }
        let newQueue = NoteQueue()
        let model = SpectralModel(sampleRate: format.sampleRate)
        let source = AVAudioSourceNode(format: format) { [parameters] _, _, count, data in
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            guard buffers.count == 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            parameters.apply(to: model)
            newQueue.drain(into: model)
            model.render(left, right, frames: count)
            return noErr
        }
        newEngine.attach(source)
        newEngine.connect(source, to: newEngine.mainMixerNode, format: format)
        try newEngine.start()
        engine = newEngine
        notes = newQueue
        return newQueue
    }
}

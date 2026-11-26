import AVFoundation
import AudioToolbox
import CoreMIDI

@objc(SpectralAUFactory)
final class SpectralAUFactory: NSObject, AUAudioUnitFactory {
    func beginRequest(with context: NSExtensionContext) {}

    func createAudioUnit(with description: AudioComponentDescription) throws -> AUAudioUnit {
        try SpectralAudioUnit(componentDescription: description, options: [])
    }
}

final class SpectralAudioUnit: AUAudioUnit {
    private let output: AUAudioUnitBus
    private var outputs: AUAudioUnitBusArray!
    private var inputs: AUAudioUnitBusArray!
    private var renderer: InstrumentRender?
    private let parameters = SpectralParameters()

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        output = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        output.maximumChannelCount = 2
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [output])
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])

        let bundle = Bundle(for: SpectralAUFactory.self)
        let controls = SpectralParameter.allCases.map { control in
            let parameter = AUParameterTree.createParameter(
                withIdentifier: control.identifier,
                name: NSLocalizedString(control.title, bundle: bundle, comment: ""),
                address: AUParameterAddress(control.rawValue), min: 0, max: 100, unit: .percent,
                unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable],
                valueStrings: nil, dependentParameters: nil
            )
            parameter.value = Float(control.defaultPercent)
            return parameter
        }
        let tree = AUParameterTree.createTree(withChildren: controls)
        tree.implementorValueObserver = { [parameters] parameter, value in
            if let control = UInt32(exactly: parameter.address).flatMap(SpectralParameter.init(rawValue:)) {
                parameters.set(control, value)
            }
        }
        tree.implementorValueProvider = { [parameters] parameter in
            guard let control = UInt32(exactly: parameter.address).flatMap(SpectralParameter.init(rawValue:)) else { return 0 }
            return parameters.get(control)
        }
        parameterTree = tree
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override var channelCapabilities: [NSNumber]? { [0, 1, 0, 2] }

    override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        bus === output && Self.supports(format)
    }

    override func allocateRenderResources() throws {
        guard Self.supports(output.format), maximumFramesToRender > 0 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        try super.allocateRenderResources()
        renderer = InstrumentRender(sampleRate: output.format.sampleRate, capacity: maximumFramesToRender)
    }

    override func deallocateRenderResources() {
        renderer = nil
        super.deallocateRenderResources()
    }

    override func reset() {
        super.reset()
        renderer?.clear()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] flags, timestamp, count, bus, output, events, _ in
            guard let self, let renderer = self.renderer else { return kAudioUnitErr_Uninitialized }
            guard bus == 0 else { return kAudioUnitErr_InvalidElement }
            guard count <= renderer.capacity else { return kAudioUnitErr_TooManyFramesToProcess }
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            self.parameters.apply(to: renderer.model)
            return renderer.render(frames: count, time: timestamp.pointee.mSampleTime, output: output,
                                   events: events, parameters: self.parameters)
        }
    }

    private static func supports(_ format: AVAudioFormat) -> Bool {
        (44_100...96_000).contains(format.sampleRate) &&
            (1...2).contains(format.channelCount) &&
            format.commonFormat == .pcmFormatFloat32 && !format.isInterleaved
    }
}

/// Per-instance render state. The host serializes render and resource lifecycle calls.
private final class InstrumentRender {
    let model: SpectralModel
    let capacity: AUAudioFrameCount
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private var keys = [UInt16](repeating: 0, count: 128)
    private var soft = false

    init(sampleRate: Double, capacity: AUAudioFrameCount) {
        self.capacity = capacity
        model = SpectralModel(sampleRate: sampleRate)
        scratchLeft = .allocate(capacity: Int(capacity))
        scratchRight = .allocate(capacity: Int(capacity))
    }

    deinit {
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    func clear() {
        model.releaseAll()
        for note in keys.indices { keys[note] = 0 }
        soft = false
    }

    func render(frames: AUAudioFrameCount, time: Float64, output: UnsafeMutablePointer<AudioBufferList>,
                events: UnsafePointer<AURenderEvent>?, parameters: SpectralParameters) -> AUAudioUnitStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        guard (1...2).contains(buffers.count) else { return kAudioUnitErr_FormatNotSupported }
        let size = frames * UInt32(MemoryLayout<Float>.stride)
        for index in buffers.indices {
            if buffers[index].mData == nil {
                buffers[index].mData = UnsafeMutableRawPointer(index == 0 ? scratchLeft : scratchRight)
            } else if buffers[index].mDataByteSize < size {
                return kAudio_ParamError
            }
            buffers[index].mDataByteSize = size
        }
        let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
        let right = buffers.count == 2 ? buffers[1].mData!.assumingMemoryBound(to: Float.self) : scratchRight

        var rendered = 0
        var event = events
        while let current = event {
            let head = current.pointee.head
            let timeOffset = Double(head.eventSampleTime) - time
            if timeOffset.isFinite && timeOffset >= Double(frames) { break }
            let offset = max(rendered, timeOffset > 0 && timeOffset.isFinite ? Int(timeOffset) : 0)
            if offset > rendered {
                model.render(left + rendered, right + rendered, frames: UInt32(offset - rendered))
                rendered = offset
            }
            switch head.eventType {
            case .MIDI:
                let midi = current.pointee.MIDI
                if midi.length == 3, let message = SpectralMIDI(status: midi.data.0, first: midi.data.1, second: midi.data.2) {
                    handle(message)
                }
            case .parameter, .parameterRamp:
                let parameter = current.pointee.parameter
                if let address = UInt32(exactly: parameter.parameterAddress),
                   let control = SpectralParameter(rawValue: address), parameter.value.isFinite {
                    parameters.set(control, parameter.value)
                    model.setParameter(control, percent: parameters.get(control))
                }
            default:
                break
            }
            event = head.next.map { UnsafePointer($0) }
        }
        model.render(left + rendered, right + rendered, frames: frames - UInt32(rendered))
        if buffers.count == 1 {
            for index in 0..<Int(frames) { left[index] = (left[index] + right[index]) * 0.5 }
        }
        return noErr
    }

    private func handle(_ event: SpectralMIDI) {
        switch event {
        case let .press(channel, note, velocity):
            keys[note] |= UInt16(1) << channel
            model.noteOn(note, velocity: Float(velocity) / 127, soft: soft)
        case let .release(channel, note):
            keys[note] &= ~(UInt16(1) << channel)
            if keys[note] == 0 { model.noteOff(note) }
        case let .damper(value):
            model.sustain(Float(value) / 127)
        case let .soft(down):
            soft = down
        case .panic:
            clear()
        }
    }
}

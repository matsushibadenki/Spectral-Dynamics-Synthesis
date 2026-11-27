import AVFoundation
import AudioToolbox
import Foundation

private final class Probe {
    let unit: HostedSynthAudioUnit
    let buffer: AVAudioPCMBuffer
    let render: AUInternalRenderBlock
    var flags = AudioUnitRenderActionFlags()
    var time = AudioTimeStamp()

    init(_ patch: SynthParameters, rate: Double = 48_000) throws {
        let component = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice, componentSubType: 0x53445332,
            componentManufacturer: 0x53704479, componentFlags: 0, componentFlagsMask: 0
        )
        unit = try HostedSynthAudioUnit(componentDescription: component)
        unit.maximumFramesToRender = 256
        unit.parameterStorage.set { $0 = patch }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        try unit.outputBusses[0].setFormat(format)
        try unit.allocateRenderResources()
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
        render = unit.internalRenderBlock
        time.mFlags = .sampleTimeValid
    }

    deinit { unit.deallocateRenderResources() }

    func block(event: UnsafePointer<AURenderEvent>? = nil) -> [Float] {
        precondition(render(&flags, &time, 256, 0, buffer.mutableAudioBufferList, event, nil) == noErr)
        time.mSampleTime += 256
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 256))
        precondition(samples.allSatisfy(\.isFinite))
        return samples
    }

    func note() -> [Float] {
        var on = AURenderEvent(MIDI: AUMIDIEvent(next: nil, eventSampleTime: Int64(time.mSampleTime) + 64, eventType: .MIDI,
            reserved: 0, length: 3, cable: 0, data: (0x90, 60, 127)))
        let first = withUnsafePointer(to: &on) { block(event: $0) }
        precondition(first.prefix(64).allSatisfy { $0 == 0 })
        return (0..<40).flatMap { _ in block() }
    }
}

private func rms(_ signal: [Float]) -> Float {
    sqrtf(signal.reduce(0) { $0 + $1 * $1 } / Float(signal.count))
}

private func checkHostControls() throws {
    let probe = try Probe(SynthParameters())
    let tree = probe.unit.parameterTree!
    let expected = Array(0..<26) + Array(100..<122) + [200, 201] + Array(300..<309)
    precondition(tree.allParameters.map(\.address).sorted() == expected.map(UInt64.init))
    precondition(tree.parameter(withAddress: 200)?.identifier == "pitchWheel")
    precondition(tree.parameter(withAddress: 300)?.identifier == "sdsBlend")
    for parameter in tree.allParameters {
        // Go through the host's render-event path, including the pending-edit bitmask.
        let control = SynthAUControls.all[SynthAUControls.indexByAddress[parameter.address]!]
        parameter.value = parameter.minValue
        precondition(control.read(from: probe.unit.parameterStorage.snapshot()) == parameter.minValue)
        let target = parameter.maxValue
        var event = AURenderEvent(parameter: AUParameterEvent(next: nil, eventSampleTime: AUEventSampleTimeImmediate,
            eventType: .parameter, reserved: (0, 0, 0), rampDurationSampleFrames: 0,
            parameterAddress: parameter.address, value: target))
        _ = withUnsafePointer(to: &event) { probe.block(event: $0) }
        let rendered = control.read(from: probe.unit.parameterStorage.snapshot())
        precondition(rendered == target, "Scheduled \(parameter.identifier): expected \(target), got \(rendered)")
    }
}

private func checkEffectUpdates() throws {
    let effects = SharedEffects()
    let initial = effects.trySnapshot(after: nil)!
    precondition(effects.trySnapshot(after: initial.revision) == nil)
    var document = FXDocument.initial
    let pedal = EffectKind.pedal.rawValue
    document.nodes[pedal].settings.enabled = true
    document.nodes[pedal].settings.mode = 3
    effects.set(try document.configuration(), document: document)
    let edit = effects.trySnapshot(after: initial.revision)!
    precondition(edit.configuration.settings[pedal].mode == 3)
    effects.sendLoop(1)
    let command = effects.trySnapshot(after: edit.revision)!
    precondition(command.configuration.settings[pedal].loopAction == 1)
    effects.reportLoop(state: 1, seconds: 0.5)
    precondition(effects.trySnapshot(after: command.revision) == nil)
    effects.resetLoop()
    precondition(effects.trySnapshot(after: command.revision)?.configuration.settings[pedal].loopAction == 0)

    // A new render allocation must pick up the routing even if no UI edit follows.
    let probe = try Probe(SynthParameters())
    var muted = FXDocument.initial
    muted.edges = []
    probe.unit.effectStorage.set(try muted.configuration(), document: muted)
    _ = probe.note()
    probe.unit.deallocateRenderResources()
    try probe.unit.allocateRenderResources()
    let output = probe.note()
    precondition(output.allSatisfy { $0 == 0 })
}

@main struct SpectralIntegration {
    static func main() throws {
        try checkHostControls()
        try checkEffectUpdates()
        print("AU: all 59 automation addresses, FX updates, and routing after reallocation passed")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var programs = Set<Data>()
        for preset in InstrumentPreset.allCases {
            let patch = preset.applying(to: SynthParameters())
            programs.insert(try encoder.encode(patch))
            let output = try Probe(patch).note()
            precondition(rms(output) > 0.0001, "\(preset.rawValue) produced no measurable signal")
        }
        precondition(programs.count == InstrumentPreset.allCases.count)
        print("Orchestra: all \(programs.count) instrument programs produced distinct settings and audible-level output")

        var patch = SynthParameters()
        patch.oscBLevel = 0
        patch.oscALevel = 0.8
        patch.envBAttack = 0.001
        patch.envBSustain = 1
        patch.filterEnvAmount = 0
        patch.resonance = 0
        patch.cutoffNorm = 0.85
        patch.oscASaw = false
        patch.oscAPulse = false
        let spectral = try Probe(patch)
        let dry = spectral.note()
        let monitored = spectral.unit.outputScope.snapshot()
        precondition(monitored?.sampleRate == 48_000)
        precondition(monitored?.samples.last?.x == dry.last)
        precondition(monitored?.samples.contains { abs($0.x) > 0.002 } == true)
        precondition(rms(dry) > 0.002, "Pure SDS must reach the AU output with analog waves off")

        patch.cutoffNorm = 0.13
        let lowpass = try Probe(patch).note()
        precondition(rms(lowpass) < rms(dry) * 0.8, "SDS must feed the shared filter")

        patch.cutoffNorm = 0.85
        patch.envBAttack = 3
        let slow = try Probe(patch).note()
        precondition(rms(Array(slow.prefix(2048))) < rms(Array(dry.prefix(2048))) * 0.65,
                     "The shared VCA envelope must control SDS")

        let parameter = spectral.unit.parameterTree!.parameter(withAddress: 301)!
        parameter.value = 0.75
        let restored = try Probe(patch)
        restored.unit.fullState = spectral.unit.fullState
        precondition(restored.unit.parameterStorage.snapshot().spectral.timbre == 0.75)
        precondition(Rev3Program(spectral.unit.parameterStorage.snapshot())
            .applying(to: patch)?.spectral.timbre == 0.75)

        patch.spectral.blend = 0
        let bypassed = try Probe(patch).note()
        precondition(rms(bypassed) < rms(dry) * 0.05, "Zero SDS blend must bypass the oscillator")
        patch.spectral.blend = 1
        patch.spectral.timbre = 1
        patch.expression.enabled = true
        patch.envBAttack = 0.001
        patch.oscSync = true
        patch.polyModOscB = 0.24
        patch.polyModToFreqA = true
        let polyphonic = try Probe(patch)
        for note in [48, 52, 55, 59, 60, 64, 67, 71] {
            polyphonic.unit.hostNoteOn(note, velocity: 0.9, parameters: patch)
        }
        let start = ProcessInfo.processInfo.systemUptime
        var peak: Float = 0
        for _ in 0..<96 {
            peak = max(peak, polyphonic.block().map(abs).max() ?? 0)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        precondition(peak > 0.001 && peak <= 1)
        print("SDS AU: scheduled MIDI, oscillator blend, shared filter and VCA, automation and state passed")
        print("SDS AU: 8 voices with sync and Poly-Mod rendered 512 ms of audio in \(Int(elapsed * 1000)) ms")
    }
}

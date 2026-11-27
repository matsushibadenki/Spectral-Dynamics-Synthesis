import AudioToolbox

/// Each entry defines both the host-visible parameter and its binding to a voice patch.
struct SynthAUControl {
    enum Binding {
        case knob(Rev3Knob)
        case toggle(Rev3Switch)
        case wheel(WritableKeyPath<SynthParameters, Float>, ClosedRange<Float>)
    }

    let address: AUParameterAddress
    let identifier: String
    let name: String
    let binding: Binding

    func read(from patch: SynthParameters) -> Float {
        switch binding {
        case .knob(let knob): return patch[keyPath: knob.key]
        case .toggle(let toggle): return patch[keyPath: toggle.key] ? 1 : 0
        case .wheel(let key, _): return patch[keyPath: key]
        }
    }

    func write(_ value: Float, to patch: inout SynthParameters) {
        guard value.isFinite else { return }
        switch binding {
        case .knob(let knob): patch[keyPath: knob.key] = knob.clamped(value)
        case .toggle(let toggle): patch[keyPath: toggle.key] = value >= 0.5
        case .wheel(let key, let range): patch[keyPath: key] = min(range.upperBound, max(range.lowerBound, value))
        }
    }

    func makeParameter() -> AUParameter {
        let range: ClosedRange<Float>
        let unit: AudioUnitParameterUnit
        switch binding {
        case .knob(let knob): range = knob.range; unit = .generic
        case .toggle: range = 0...1; unit = .boolean
        case .wheel(_, let bounds): range = bounds; unit = .generic
        }
        return AUParameterTree.createParameter(withIdentifier: identifier, name: name, address: address,
            min: range.lowerBound, max: range.upperBound, unit: unit, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil, dependentParameters: nil)
    }
}

enum SynthAUControls {
    // Keep existing host addresses and parameter-tree order for saved automation.
    static let all: [SynthAUControl] = {
        var controls = Rev3.knobs.enumerated().map { index, knob in
            SynthAUControl(address: UInt64(index), identifier: knob.id, name: knob.names[0], binding: .knob(knob))
        }
        controls += Rev3.switches.enumerated().map { index, toggle in
            SynthAUControl(address: UInt64(100 + index), identifier: toggle.id, name: toggle.names[0], binding: .toggle(toggle))
        }
        controls += SpectralOscillatorParameters.knobs.enumerated().map { index, knob in
            SynthAUControl(address: UInt64(300 + index), identifier: knob.id,
                name: instrumentText(knob.names[0], knob.names[1], knob.names[2]), binding: .knob(knob))
        }
        controls.append(.init(address: 200, identifier: "pitchWheel", name: "Pitch wheel", binding: .wheel(\.pitchWheel, -1...1)))
        controls.append(.init(address: 201, identifier: "modWheel", name: "Modulation wheel", binding: .wheel(\.modWheel, 0...1)))
        precondition(controls.count <= UInt64.bitWidth, "Pending AU edits must fit in the render bitmask")
        return controls
    }()

    static let indexByAddress = Dictionary(uniqueKeysWithValues: all.indices.map { (all[$0].address, $0) })
}

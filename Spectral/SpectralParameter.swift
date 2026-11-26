import Synchronization

enum SpectralParameter: UInt32, CaseIterable {
    case sidebandBalance = 0
    case diffusion = 1
    case modulationIndex = 2
    case spectralTilt = 3
    case release = 4
    case phaseMotion = 5
    case flow = 6
    case coupling = 7
    case volume = 8
    case timbre = 9

    var identifier: String { String(describing: self) }

    var defaultPercent: Int {
        switch self {
        case .diffusion: 18
        case .modulationIndex: 65
        case .spectralTilt: 78
        case .phaseMotion: 35
        case .coupling: 38
        default: 50
        }
    }

    var title: String {
        switch self {
        case .sidebandBalance: "Sideband balance"
        case .diffusion: "Diffusion"
        case .modulationIndex: "Modulation index"
        case .spectralTilt: "Spectral tilt"
        case .release: "Release"
        case .phaseMotion: "Phase motion"
        case .flow: "Flow"
        case .coupling: "Coupling"
        case .volume: "Volume"
        case .timbre: "Timbre"
        }
    }

    static let timbreNames = ["Pure", "Hollow", "Saw", "Metal", "Bloom"]

    var step: Double { self == .timbre ? 25 : 1 }

    var storageKey: String { identifier + "Percent" }
}

/// Shared between control/host threads and one render callback.
final class SpectralParameters: Sendable {
    private final class Value: Sendable {
        let percent: Atomic<Float>
        init(_ percent: Int) { self.percent = Atomic(Float(percent)) }
    }

    private let controls = SpectralParameter.allCases
    private let values = SpectralParameter.allCases.map { Value($0.defaultPercent) }

    func get(_ parameter: SpectralParameter) -> Float {
        values[Int(parameter.rawValue)].percent.load(ordering: .relaxed)
    }

    func set(_ parameter: SpectralParameter, _ percent: Float) {
        guard percent.isFinite else { return }
        let clamped = min(100, max(0, percent))
        values[Int(parameter.rawValue)].percent.store(clamped, ordering: .relaxed)
    }

    func apply(to model: SpectralModel) {
        for parameter in controls {
            model.setParameter(parameter, percent: get(parameter))
        }
    }
}

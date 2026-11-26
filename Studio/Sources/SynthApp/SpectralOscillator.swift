// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/Studio/Sources/SynthApp/SpectralOscillator.swift
// SpectralOscillator.swift
// SDS（スペクトルダイナミクス合成）オシレーターの設定構造体、パラメーター定義、およびネイティブDSPブリッジ

import Foundation

struct SpectralOscillatorSettings: Codable, Equatable {
    var blend: Float = 1
    var timbre: Float = 0.62
    var modulation: Float = 0.65
    var tilt: Float = 0.75
    var balance: Float = 0.5
    var diffusion: Float = 0.25
    var flow: Float = 0.5
    var coupling: Float = 0.42
    var motion: Float = 0.35
}

enum SpectralOscillatorParameters {
    static let timbres = [
        ["Pure", "サイン", "正弦"],
        ["Hollow", "奇数倍音", "奇次谐波"],
        ["Saw", "ノコギリ", "锯齿"],
        ["Metal", "メタル", "金属"],
        ["Bloom", "ブルーム", "渐展"]
    ]

    static let knobs: [Rev3Knob] = [
        .init(id: "sdsBlend", label: "BLEND", names: ["Spectral blend", "スペクトル混合", "频谱混合"], key: \.spectral.blend, range: 0...1, curve: 0),
        .init(id: "sdsTimbre", label: "TIMBRE", names: ["Timbre", "音色", "音色"], key: \.spectral.timbre, range: 0...1, curve: 0),
        .init(id: "sdsModulation", label: "INDEX", names: ["Modulation index", "変調指数", "调制指数"], key: \.spectral.modulation, range: 0...1, curve: 0),
        .init(id: "sdsTilt", label: "TILT", names: ["Spectral tilt", "スペクトル傾斜", "频谱倾斜"], key: \.spectral.tilt, range: 0...1, curve: 0),
        .init(id: "sdsBalance", label: "BALANCE", names: ["Sideband balance", "側帯波バランス", "边带平衡"], key: \.spectral.balance, range: 0...1, curve: 0),
        .init(id: "sdsDiffusion", label: "DIFFUSION", names: ["Diffusion", "拡散", "扩散"], key: \.spectral.diffusion, range: 0...1, curve: 0),
        .init(id: "sdsFlow", label: "FLOW", names: ["Spectral flow", "移流", "频谱流动"], key: \.spectral.flow, range: 0...1, curve: 0),
        .init(id: "sdsCoupling", label: "COUPLING", names: ["Partial coupling", "倍音結合", "泛音耦合"], key: \.spectral.coupling, range: 0...1, curve: 0),
        .init(id: "sdsMotion", label: "MOTION", names: ["Phase motion", "位相の揺らぎ", "相位变化"], key: \.spectral.motion, range: 0...1, curve: 0)
    ]
}

final class SpectralOscillator {
    private let bank: OpaquePointer = sds_osc_create()

    deinit { sds_osc_destroy(bank) }

    func reset() { sds_osc_reset(bank) }

    func prepare(rate: Float, oversampling: Int, settings: SpectralOscillatorSettings) {
        sds_osc_prepare(bank, rate, UInt32(oversampling), SDSOscillatorControls(
            timbre: settings.timbre, modulation: settings.modulation, tilt: settings.tilt,
            balance: settings.balance, diffusion: settings.diffusion, flow: settings.flow,
            coupling: settings.coupling, motion: settings.motion
        ))
    }

    @inline(__always) func sample(slot: Int, trigger: UInt64, phase: Double,
                                   increment: Float, depth: Float, synced: Bool) -> Float {
        sds_osc_sample(bank, UInt32(slot), trigger, phase, increment, depth, synced)
    }
}

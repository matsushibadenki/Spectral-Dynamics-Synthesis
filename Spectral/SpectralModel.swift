/// Owns one instance of the spectral DSP. Events and rendering run on
/// the same Core Audio callback, after construction on the audio worker.
final class SpectralModel {
    private let handle: OpaquePointer

    init(sampleRate: Double) {
        handle = sds_create(sampleRate)
    }

    deinit {
        sds_destroy(handle)
    }

    func noteOn(_ note: Int, velocity: Float, soft: Bool = false) {
        sds_note_on(handle, UInt32(note), velocity, soft)
    }

    func noteOff(_ note: Int) {
        sds_note_off(handle, UInt32(note))
    }

    func sustain(_ value: Float) {
        sds_sustain(handle, value)
    }

    func releaseAll() {
        sds_all_off(handle)
    }

    func setParameter(_ parameter: SpectralParameter, percent: Float) {
        sds_set_parameter(handle, parameter.rawValue, percent / 100)
    }

    func render(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: UInt32) {
        sds_render(handle, left, right, frames)
    }
}

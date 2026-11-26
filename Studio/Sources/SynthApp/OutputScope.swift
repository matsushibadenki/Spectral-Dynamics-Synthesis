import Foundation

/// One render producer and one display consumer. The render thread skips a
/// block if the display owns the lock, so it never waits for a snapshot.
final class OutputScope {
    struct Snapshot {
        let samples: [SIMD2<Float>]
        let sampleRate: Float
    }

    private static let capacity = 2048
    private let lock = NSLock()
    private let storage = UnsafeMutablePointer<SIMD2<Float>>.allocate(capacity: capacity)
    private var cursor = 0
    private var count = 0
    private var sampleRate: Float = 48_000
    private var lastWrite: UInt64 = 0

    init() { storage.initialize(repeating: .zero, count: Self.capacity) }

    deinit {
        storage.deinitialize(count: Self.capacity)
        storage.deallocate()
    }

    func capture(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int, sampleRate: Float) {
        guard frames > 0, lock.try() else { return }
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        if self.sampleRate != sampleRate || now - lastWrite > 250_000_000 {
            count = 0
            cursor = 0
        }
        self.sampleRate = sampleRate
        for i in max(0, frames - Self.capacity)..<frames {
            storage[cursor] = SIMD2(left[i], right[i])
            cursor = (cursor + 1) & (Self.capacity - 1)
        }
        count = min(Self.capacity, count + frames)
        lastWrite = now
    }

    func snapshot() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0, DispatchTime.now().uptimeNanoseconds - lastWrite < 250_000_000 else { return nil }
        let start = (cursor - count) & (Self.capacity - 1)
        let samples = (0..<count).map { storage[(start + $0) & (Self.capacity - 1)] }
        return Snapshot(samples: samples, sampleRate: sampleRate)
    }
}

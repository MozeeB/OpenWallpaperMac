import Synchronization

/// Lock-free single-producer / single-consumer ring buffer of `Float` samples.
///
/// The producer is the real-time Core Audio IO thread, which must never lock or allocate;
/// `write` only copies and publishes an index with release ordering.
public final class SPSCRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let head = Atomic<Int>(0)  // next write position (producer-owned)
    private let tail = Atomic<Int>(0)  // next read position (consumer-owned)

    public init(capacity: Int) {
        precondition(capacity > 1, "capacity must be > 1")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Number of samples ready to read.
    public var availableToRead: Int {
        let written = head.load(ordering: .acquiring)
        let read = tail.load(ordering: .acquiring)
        return (written - read + capacity) % capacity
    }

    /// Copies as many samples as fit; returns the count written. Real-time safe.
    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        let written = head.load(ordering: .relaxed)
        let read = tail.load(ordering: .acquiring)
        let free = (read - written - 1 + capacity) % capacity
        let count = min(free, samples.count)
        guard count > 0, let base = samples.baseAddress else { return 0 }
        let first = min(count, capacity - written)
        (storage + written).update(from: base, count: first)
        if count > first { storage.update(from: base + first, count: count - first) }
        head.store((written + count) % capacity, ordering: .releasing)
        return count
    }

    /// Copies up to `buffer.count` samples out; returns the count read.
    @discardableResult
    public func read(into buffer: UnsafeMutableBufferPointer<Float>) -> Int {
        let read = tail.load(ordering: .relaxed)
        let written = head.load(ordering: .acquiring)
        let available = (written - read + capacity) % capacity
        let count = min(available, buffer.count)
        guard count > 0, let base = buffer.baseAddress else { return 0 }
        let first = min(count, capacity - read)
        base.update(from: storage + read, count: first)
        if count > first { (base + first).update(from: storage, count: count - first) }
        tail.store((read + count) % capacity, ordering: .releasing)
        return count
    }

    /// Discards everything currently buffered (consumer side).
    public func drain() {
        tail.store(head.load(ordering: .acquiring), ordering: .releasing)
    }
}

public extension SPSCRingBuffer {
    @discardableResult
    func write(_ samples: [Float]) -> Int {
        samples.withUnsafeBufferPointer { write($0) }
    }

    func read(count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        let got = output.withUnsafeMutableBufferPointer { read(into: $0) }
        return Array(output.prefix(got))
    }
}

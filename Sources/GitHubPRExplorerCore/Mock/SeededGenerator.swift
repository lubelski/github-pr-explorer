import Foundation

/// A small deterministic random number generator (SplitMix64) with its own helpers.
///
/// The mock world must come out byte for byte the same on every run and every Mac, so it
/// never uses the standard library's random APIs, whose algorithms are not promised to stay
/// the same between Swift releases. Everything random in the mock world goes through here.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Seeds from text with 64-bit FNV-1a, so each pull request can have its own stream
    /// and adding one never shifts another.
    init(seed text: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// A whole number in the range, both ends included.
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        return range.lowerBound + Int(next() % span)
    }

    /// True with probability `probability`, from 0 to 1.
    mutating func chance(_ probability: Double) -> Bool {
        let unit = Double(next() >> 11) / Double(UInt64(1) << 53)
        return unit < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        precondition(!items.isEmpty, "pick from an empty list")
        return items[int(0...(items.count - 1))]
    }

    /// Picks by weight. Weights must be positive.
    mutating func pick<T>(weighted items: [(T, Int)]) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var roll = int(0...(total - 1))
        for (item, weight) in items {
            if roll < weight { return item }
            roll -= weight
        }
        return items[items.count - 1].0
    }

    /// A Fisher-Yates shuffle.
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var items = items
        guard items.count > 1 else { return items }
        for index in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(index, int(0...index))
        }
        return items
    }

    /// Up to `count` distinct items, in a random order.
    mutating func pick<T>(_ items: [T], count: Int) -> [T] {
        Array(shuffled(items).prefix(count))
    }

    mutating func hex(length: Int) -> String {
        let digits = Array("0123456789abcdef")
        return String((0..<length).map { _ in digits[int(0...15)] })
    }
}

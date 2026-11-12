import Foundation
import Testing

@testable import NopeSigning

/// A small, seeded random number generator (SplitMix64), so each fuzz run is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The reference model the in-memory file is checked against: a plain array and an index.
struct ReferenceFile {
    var bytes: [UInt8]
    var position = 0

    mutating func read(_ count: Int) -> [UInt8] {
        guard count > 0, position < bytes.count else { return [] }
        let end = min(bytes.count, position + count)
        defer { position = end }
        return Array(bytes[position..<end])
    }

    mutating func write(_ new: [UInt8]) {
        while bytes.count < position { bytes.append(0) }
        for (index, byte) in new.enumerated() {
            if position + index < bytes.count { bytes[position + index] = byte } else { bytes.append(byte) }
        }
        position += new.count
    }

    mutating func seek(_ offset: Int, _ origin: Int) -> Int {
        let base: Int
        switch origin {
        case 0: base = 0
        case 1: base = position
        case 2: base = bytes.count
        default: return -1
        }
        guard base + offset >= 0 else { return -1 }
        position = base + offset
        return position
    }
}

struct InMemoryStreamTests {
    /// Random reads, writes and seeks through the pointer callbacks, compared with the reference.
    @Test(arguments: 1...20)
    func fuzzAgainstReference(seed: UInt64) {
        var random = SeededGenerator(state: seed)
        let initial = (0..<Int.random(in: 0...64, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
        let file = InMemoryFile(Data(initial))
        var reference = ReferenceFile(bytes: initial)
        for _ in 0..<500 {
            switch Int.random(in: 0...2, using: &random) {
            case 0:
                let count = Int.random(in: -2...40, using: &random)
                var buffer = [UInt8](repeating: 0xAA, count: max(0, count))
                let read = buffer.withUnsafeMutableBytes { InMemoryStream.read(file, into: $0.baseAddress ?? UnsafeMutableRawPointer(bitPattern: 1)!, count: count) }
                if count < 0 {
                    #expect(read == -1)
                } else {
                    let expected = reference.read(count)
                    #expect(read == expected.count)
                    #expect(Array(buffer.prefix(max(0, read))) == expected)
                    // Bytes past what was read are untouched.
                    #expect(buffer.dropFirst(max(0, read)).allSatisfy { $0 == 0xAA })
                }
            case 1:
                let new = (0..<Int.random(in: 0...40, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
                let written = new.withUnsafeBytes { InMemoryStream.write(file, from: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, count: new.count) }
                #expect(written == new.count)
                reference.write(new)
            default:
                let origin = Int.random(in: 0...3, using: &random)
                let offset = Int.random(in: -80...80, using: &random)
                #expect(file.seek(by: offset, from: origin) == reference.seek(offset, origin))
            }
            #expect(file.bytes == reference.bytes)
            #expect(file.position == reference.position)
        }
        #expect(file.data == Data(reference.bytes))
    }

    @Test func negativeWriteCountFails() {
        let file = InMemoryFile()
        let byte: [UInt8] = [1]
        let result = byte.withUnsafeBytes { InMemoryStream.write(file, from: $0.baseAddress!, count: -1) }
        #expect(result == -1)
        #expect(file.bytes.isEmpty)
    }

    @Test func seekingFarFailsWithoutMoving() {
        let file = InMemoryFile(Data([1, 2, 3]))
        #expect(file.seek(by: 2, from: 0) == 2)
        #expect(file.seek(by: .max, from: 1) == -1)
        #expect(file.seek(by: -3, from: 1) == -1)
        #expect(file.seek(by: 0, from: 7) == -1)
        #expect(file.position == 2)
    }

    @Test func writingPastTheEndFillsTheGapWithZeros() {
        let file = InMemoryFile(Data([1]))
        _ = file.seek(by: 2, from: 2)
        file.write([9])
        #expect(file.bytes == [1, 0, 0, 9])
    }

    @Test func flushAlwaysSucceeds() {
        #expect(InMemoryStream.flush() == 0)
    }

    @Test func streamIsCreated() throws {
        _ = try InMemoryStream.make(InMemoryFile())
    }
}

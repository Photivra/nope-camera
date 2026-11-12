import Foundation

/// A growable byte buffer with a read and write position, for C2PA streams kept in memory.
///
/// Privacy rule: photos go from memory to Photos and never linger on disk (AGENTS.md, "Photos
/// never linger"), so the C2PA library reads the source file from, and writes the signed file
/// to, memory instead of temporary files. This type holds the logic, in safe Swift;
/// `InMemoryStream.swift` connects it to the library's pointer-based callbacks.
///
/// It behaves like a file opened for reading and writing: reading past the end returns no
/// bytes, writing past the end fills the gap with zeros, and seeking before the start fails.
final class InMemoryFile {
    /// Where a seek offset is measured from. The raw values match the C2PA library's
    /// `C2paSeekMode` (`c2pa.h`: `Start = 0`, `Current = 1`, `End = 2`).
    enum SeekOrigin: Int, CaseIterable {
        /// The start of the file.
        case start = 0
        /// The current position.
        case current = 1
        /// The end of the file.
        case end = 2
    }

    /// The result the library's callbacks use for an error.
    static let failure = -1

    /// The file's bytes.
    private(set) var bytes: [UInt8]

    /// The position of the next read or write, in bytes from the start.
    private(set) var position = 0

    /// Creates a file holding a copy of some bytes, positioned at the start.
    ///
    /// - Parameter data: The initial contents. Pass empty data for a destination file.
    init(_ data: Data = Data()) {
        bytes = [UInt8](data)
    }

    /// The file's contents.
    var data: Data { Data(bytes) }

    /// Reads up to `count` bytes from the current position and moves past them.
    ///
    /// - Parameter count: The most bytes to read. A negative count reads nothing.
    /// - Returns: The bytes read: fewer than `count` at the end of the file, none past it.
    func read(upTo count: Int) -> ArraySlice<UInt8> {
        let end = min(bytes.count, position + max(0, count))
        guard end > position else { return [] }
        let slice = bytes[position..<end]
        position = end
        return slice
    }

    /// Writes bytes at the current position, overwriting or extending the file, and moves past
    /// them. Writing beyond the end first fills the gap with zeros.
    ///
    /// - Parameter newBytes: The bytes to write.
    func write(_ newBytes: some Collection<UInt8>) {
        if position > bytes.count {
            bytes.append(contentsOf: repeatElement(0, count: position - bytes.count))
        }
        let overlap = min(newBytes.count, bytes.count - position)
        bytes.replaceSubrange(position..<(position + overlap), with: newBytes)
        position += newBytes.count
    }

    /// Moves the position.
    ///
    /// - Parameters:
    ///   - offset: The offset in bytes, which may be negative.
    ///   - rawOrigin: The library's seek mode: 0 from the start, 1 from the current position,
    ///     2 from the end.
    /// - Returns: The new position, or ``failure`` for an unknown mode or a position before the
    ///   start, in which case the position doesn't change.
    func seek(by offset: Int, from rawOrigin: Int) -> Int {
        guard let origin = SeekOrigin(rawValue: rawOrigin) else { return Self.failure }
        let base =
            switch origin {
            case .start: 0
            case .current: position
            case .end: bytes.count
            }
        let (target, overflow) = base.addingReportingOverflow(offset)
        guard !overflow, target >= 0 else { return Self.failure }
        position = target
        return target
    }
}

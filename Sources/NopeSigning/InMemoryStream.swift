import C2PA
import class C2PA.Stream
import Foundation

/// Connects an ``InMemoryFile`` to the C2PA library's pointer-based stream callbacks.
///
/// This is the only file in `NopeSigning` that uses pointer APIs, so it is listed in
/// `security/allowed-unsafe.txt`. Each callback checks its count, copies at most that many bytes,
/// and does nothing else; the position and growth logic is in ``InMemoryFile``, in safe Swift.
/// Both are fuzz-tested against a reference model (`InMemoryStreamTests`).
enum InMemoryStream {
    /// Creates a readable, writable, seekable C2PA stream over a file in memory.
    ///
    /// - Parameter file: The file. The stream keeps a strong reference to it.
    /// - Returns: The stream.
    /// - Throws: `C2PAError` if the library can't create the stream.
    static func make(_ file: InMemoryFile) throws -> Stream {
        try Stream(
            read: { buffer, count in read(file, into: buffer, count: count) },
            seek: { offset, mode in file.seek(by: offset, from: Int(mode.rawValue)) },
            write: { buffer, count in write(file, from: buffer, count: count) },
            flush: flush)
    }

    /// Flushes the stream. Memory needs no flushing, so it always succeeds.
    ///
    /// - Returns: 0, the library's success value.
    static func flush() -> Int {
        0
    }

    /// Copies up to `count` bytes from the file into the library's buffer.
    ///
    /// - Parameters:
    ///   - file: The file to read from.
    ///   - buffer: The library's buffer, at least `count` bytes long.
    ///   - count: The buffer's size in bytes.
    /// - Returns: The number of bytes copied (0 at the end of the file), or
    ///   ``InMemoryFile/failure`` for a negative count.
    static func read(_ file: InMemoryFile, into buffer: UnsafeMutableRawPointer, count: Int) -> Int {
        guard count >= 0 else { return InMemoryFile.failure }
        let slice = file.read(upTo: count)
        UnsafeMutableRawBufferPointer(start: buffer, count: count).copyBytes(from: slice)
        return slice.count
    }

    /// Writes `count` bytes from the library's buffer into the file.
    ///
    /// - Parameters:
    ///   - file: The file to write to.
    ///   - buffer: The library's buffer, holding `count` bytes.
    ///   - count: The number of bytes to write.
    /// - Returns: The number of bytes written, or ``InMemoryFile/failure`` for a negative count.
    static func write(_ file: InMemoryFile, from buffer: UnsafeRawPointer, count: Int) -> Int {
        guard count >= 0 else { return InMemoryFile.failure }
        file.write(UnsafeRawBufferPointer(start: buffer, count: count))
        return count
    }
}

import Foundation

/// Converts pixel format codes (`OSType`, such as `'bgg4'`) to and from their four characters.
///
/// `NopeCore` publishes formats as strings, so interfaces and reports never handle raw codes.
enum FourCharacterCode {
    /// The four characters of a code, or `0x` and eight hex digits when a byte isn't printable
    /// ASCII.
    ///
    /// - Parameter code: A pixel format code.
    /// - Returns: For example `bgg4`, or `0x00000000`.
    static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> UInt32($0)) }
        guard bytes.allSatisfy(isPrintable) else { return String(format: "0x%08x", code) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The code for four printable ASCII characters.
    ///
    /// - Parameter string: Exactly four printable ASCII characters, such as `bgg4`.
    /// - Returns: The code, or `nil` if the string isn't four printable ASCII characters.
    static func code(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard bytes.count == 4, bytes.allSatisfy(isPrintable) else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// Whether a byte is printable ASCII (space through tilde).
    ///
    /// - Parameter byte: One byte of a code.
    private static func isPrintable(_ byte: UInt8) -> Bool {
        (0x20..<0x7F).contains(byte)
    }
}

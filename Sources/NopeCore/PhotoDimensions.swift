import Foundation

/// A photo size in pixels.
public struct PhotoDimensions: Equatable, Hashable, Sendable {
    /// The width, in pixels.
    public let width: Int

    /// The height, in pixels.
    public let height: Int

    /// Creates a size.
    ///
    /// - Parameters:
    ///   - width: The width, in pixels.
    ///   - height: The height, in pixels.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The number of pixels, `width × height`.
    public var pixelCount: Int {
        width * height
    }
}

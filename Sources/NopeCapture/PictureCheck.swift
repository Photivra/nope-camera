import Foundation

/// Tells a blank photo buffer from a picture, cheaply, from a few sampled bytes.
///
/// On an iPhone 16 Pro Max (iOS 27.2.1) the camera service got stuck in a state where the
/// session ran, frames arrived and auto exposure metered normally, but every delivered buffer
/// was zero-filled: the RAW DNGs were a constant fill and the video frames' luma bytes were all
/// 0, until the phone was restarted (docs/TESTING.md, "Black frames"). A sensor readout always
/// carries noise, so a real picture never has every sampled byte equal; a zero or constant fill
/// always does.
///
/// The hardware adapter reads the bytes at ``sampleOffsets(byteCount:)`` from the photo's pixel
/// buffer and ``AVFoundationCaptureBackend`` asks ``isBlank(_:)``. Reading 128 bytes costs
/// nothing next to a capture, so it runs on every photo.
enum PictureCheck {
    /// How many places in the buffer are sampled. An assumption, not a platform value: 64
    /// places spread over the whole buffer can't all land in one flat region of a real scene
    /// with sensor noise.
    static let samplePlaces = 64

    /// The fewest sampled bytes needed for a verdict; with fewer, the photo counts as a
    /// picture, so a tiny or unreadable buffer never blocks the camera.
    static let minimumSampleCount = 16

    /// The byte offsets to read: two adjacent bytes at each of ``samplePlaces`` evenly spaced
    /// places, so both bytes of a 16-bit RAW sample are read (the low byte carries the noise).
    ///
    /// - Parameter byteCount: The size of the buffer, in bytes.
    /// - Returns: Increasing offsets, each less than `byteCount`; empty when `byteCount` is 0
    ///   or less.
    static func sampleOffsets(byteCount: Int) -> [Int] {
        guard byteCount > 0 else { return [] }
        var offsets: [Int] = []
        for place in 0..<samplePlaces {
            let start = place * byteCount / samplePlaces
            for offset in [start, start + 1] where offset < byteCount && offset > (offsets.last ?? -1) {
                offsets.append(offset)
            }
        }
        return offsets
    }

    /// Whether sampled bytes come from a blank (zero-filled or constant-filled) buffer.
    ///
    /// - Parameter sample: The bytes read at ``sampleOffsets(byteCount:)``, or `nil` when the
    ///   photo had no pixel buffer to read (a compressed HEIF or JPEG; Apple's
    ///   `AVCapturePhoto.pixelBuffer` is `nil` for those).
    /// - Returns: `true` only when there are at least ``minimumSampleCount`` bytes and they are
    ///   all equal. `nil` or too few bytes give `false`: unknown is treated as a picture.
    static func isBlank(_ sample: [UInt8]?) -> Bool {
        guard let sample, sample.count >= minimumSampleCount, let first = sample.first else { return false }
        return sample.allSatisfy { $0 == first }
    }
}

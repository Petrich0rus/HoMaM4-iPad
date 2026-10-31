import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public extension H4RGBAImage {
    /// A CGImage view of the pixels (straight alpha), usable by UIKit, SwiftUI or Metal loaders.
    func cgImage() -> CGImage? {
        guard width > 0, height > 0,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func pngData() throws -> Data {
        guard let image = cgImage() else { throw H4Error.malformed("cannot encode an empty \(width)×\(height) image") }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw H4Error.malformed("PNG encoder unavailable")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw H4Error.malformed("PNG encoding failed") }
        return out as Data
    }
}

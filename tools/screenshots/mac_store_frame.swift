// Sets a window capture (with its shadow) on a 16:10 canvas the Mac App Store accepts: 2880×1800 for a
// Retina capture, 1440×900 otherwise, over a soft gradient in the app's colors.
// Usage: swift tools/screenshots/mac_store_frame.swift <window.png> <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(filePath: arguments[1]) as CFURL, nil),
      let window = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("usage: mac_store_frame.swift <window.png> <out.png>") }

let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
let scale = dpi > 100 ? 2.0 : 1.0
let canvas = CGSize(width: 1440 * scale, height: 900 * scale)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!  // App Store Connect refuses alpha
let colors = [CGColor(srgbRed: 0.98, green: 0.90, blue: 0.93, alpha: 1),
              CGColor(srgbRed: 0.91, green: 0.89, blue: 0.97, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])

// Fit the window, shadow included, inside a margin, never enlarging it.
let size = CGSize(width: window.width, height: window.height)
let fit = min(1, (canvas.width * 0.94) / size.width, (canvas.height * 0.96) / size.height)
let drawn = CGSize(width: size.width * fit, height: size.height * fit)
context.interpolationQuality = .high
context.draw(window, in: CGRect(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2,
                                width: drawn.width, height: drawn.height))

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(filePath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(arguments[2])") }

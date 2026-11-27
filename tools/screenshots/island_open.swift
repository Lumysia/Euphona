// Exits 0 when a light-mode iPhone screenshot shows the Dynamic Island expanded (the system's brief
// audio indicator), 1 otherwise. Usage: island_open <screenshot.png>
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(filePath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { exit(2) }

// Draw the strip beside the island, where a collapsed island leaves the status bar background.
let strip = CGRect(x: image.width / 2 - 150, y: 40, width: 300, height: 70)
guard let cropped = image.cropping(to: strip) else { exit(2) }
let width = cropped.width, height = cropped.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
let dark = stride(from: 0, to: pixels.count, by: 4).filter { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) < 90 }.count
exit(Double(dark) / Double(width * height) > 0.3 ? 0 : 1)

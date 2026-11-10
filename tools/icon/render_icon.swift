// Renders Euphona's app icon: the voice orb, pink and blue folding into each other.
// Usage: swift tools/icon/render_icon.swift   (writes into Euphona/Assets.xcassets/AppIcon.appiconset)
import AppKit
import SwiftUI

enum Variant { case light, dark, tinted }

let pink = Color(red: 1.00, green: 0.56, blue: 0.70)
let deepPink = Color(red: 0.91, green: 0.33, blue: 0.50)
let blue = Color(red: 0.44, green: 0.61, blue: 1.00)
let deepBlue = Color(red: 0.24, green: 0.37, blue: 0.85)

/// The orb: a 3×3 mesh with pink sweeping in from the upper left and blue from the lower right,
/// a soft specular highlight and a thin bright rim.
struct Orb: View {
    var variant: Variant

    var body: some View {
        let colors: [Color] = variant == .tinted
            ? [0.92, 0.80, 0.62, 0.82, 0.70, 0.50, 0.60, 0.46, 0.30].map { Color(white: $0) }
            : [pink, pink, blue, deepPink, pink.mix(with: blue, by: 0.45, in: .perceptual), blue,
               deepPink, blue, deepBlue]
        GeometryReader { proxy in
            let d = proxy.size.width
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.42], [0.46, 0.56], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: colors)
            .clipShape(.circle)
            .overlay {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                             center: UnitPoint(x: 0.33, y: 0.27), startRadius: 0, endRadius: d * 0.6))
                    .blendMode(.softLight)
            }
            .overlay {
                Ellipse().fill(.white.opacity(variant == .tinted ? 0.18 : 0.28))
                    .frame(width: d * 0.38, height: d * 0.2)
                    .blur(radius: d * 0.05)
                    .offset(x: -d * 0.14, y: -d * 0.27)
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: d * 0.006) }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The square artwork: background, halo and orb.
struct Artwork: View {
    var variant: Variant
    var size: CGFloat

    var body: some View {
        ZStack {
            switch variant {
            case .light:
                LinearGradient(colors: [Color(red: 0.99, green: 0.97, blue: 1.0), Color(red: 0.92, green: 0.92, blue: 0.99)],
                               startPoint: .top, endPoint: .bottom)
            case .dark:
                LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.18), Color(red: 0.04, green: 0.03, blue: 0.08)],
                               startPoint: .top, endPoint: .bottom)
            case .tinted:
                Color.black
            }
            // The halo, tinted by the orb's own colors.
            Circle()
                .fill(RadialGradient(colors: [halo.opacity(variant == .dark ? 0.55 : 0.4), halo.opacity(0)],
                                     center: .center, startRadius: size * 0.2, endRadius: size * 0.48))
                .frame(width: size, height: size)
            // The listening ring from the recording screen.
            Circle()
                .strokeBorder(AngularGradient(colors: ringColors, center: .center), lineWidth: size * 0.012)
                .frame(width: size * 0.76, height: size * 0.76)
                .opacity(variant == .light ? 0.55 : 0.7)
            Orb(variant: variant)
                .frame(width: size * 0.6, height: size * 0.6)
                .shadow(color: (variant == .light ? deepBlue : .black).opacity(variant == .light ? 0.18 : 0.4),
                        radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
    }

    private var ringColors: [Color] {
        variant == .tinted ? [Color(white: 0.75), Color(white: 0.35), Color(white: 0.75)] : [pink, blue, deepBlue, deepPink, pink]
    }

    private var halo: Color {
        variant == .tinted ? Color(white: 0.5) : pink.mix(with: blue, by: 0.5, in: .perceptual)
    }
}

/// macOS 26 icons carry their own rounded square: an 824-point body on a 1024 canvas with a soft shadow.
struct MacIcon: View {
    var size: CGFloat

    var body: some View {
        let body = size * 824 / 1024
        let shape = RoundedRectangle(cornerRadius: body * 0.225, style: .continuous)
        Artwork(variant: .light, size: body)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.black.opacity(0.06), lineWidth: max(1, size / 512)) }
            .shadow(color: .black.opacity(0.22), radius: size * 0.02, y: size * 0.012)
            .frame(width: size, height: size)
    }
}

@MainActor
func png(_ view: some View, size: CGFloat, opaque: Bool) -> Data {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    renderer.isOpaque = opaque
    guard let image = renderer.cgImage else { fatalError("render failed") }
    // App Store icons for iOS must not have an alpha channel.
    let info: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
func main() throws {
    let folder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                     : "Euphona/Assets.xcassets/AppIcon.appiconset")
    var images: [[String: Any]] = []

    for (variant, name, appearance) in [(Variant.light, "icon-ios.png", nil as String?),
                                        (.dark, "icon-ios-dark.png", "dark"),
                                        (.tinted, "icon-ios-tinted.png", "tinted")] {
        try png(Artwork(variant: variant, size: 1024), size: 1024, opaque: true).write(to: folder.appending(path: name))
        var entry: [String: Any] = ["filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
        if let appearance { entry["appearances"] = [["appearance": "luminosity", "value": appearance]] }
        images.append(entry)
    }

    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let name = "icon-mac-\(pixels).png"
            try png(MacIcon(size: CGFloat(pixels)), size: CGFloat(pixels), opaque: false).write(to: folder.appending(path: name))
            images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
        }
    }

    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appending(path: "Contents.json"))
    print("wrote \(images.count) icon entries to \(folder.path)")
}

try MainActor.assumeIsolated { try main() }

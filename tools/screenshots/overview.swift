// Lays screenshots out in a grid with rounded corners on a light background, for the README.
// Usage: swift tools/screenshots/overview.swift <out.png> <columns> <width of one screen> <shot.png>...
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 4, let columns = Int(arguments[arguments.startIndex + 1]),
      let cellWidth = Double(arguments[arguments.startIndex + 2]) else {
    FileHandle.standardError.write(Data("usage: overview.swift <out.png> <columns> <width> <shot.png>...\n".utf8))
    exit(1)
}
let output = URL(filePath: arguments[arguments.startIndex])
let images = arguments.dropFirst(3).map { path -> CGImage in
    guard let source = CGImageSourceCreateWithURL(URL(filePath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
        exit(1)
    }
    return image
}

let aspect = Double(images[0].height) / Double(images[0].width)
let cellHeight = (cellWidth * aspect).rounded()
let gap = (cellWidth * 0.06).rounded()
let radius = cellWidth * 0.11
let rows = (images.count + columns - 1) / columns
let width = Int(Double(columns) * cellWidth + Double(columns + 1) * gap)
let height = Int(Double(rows) * cellHeight + Double(rows + 1) * gap)

let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
context.setFillColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
for (index, image) in images.enumerated() {
    let column = index % columns, row = index / columns
    let frame = CGRect(x: gap + Double(column) * (cellWidth + gap),
                       y: Double(height) - gap - cellHeight - Double(row) * (cellHeight + gap),
                       width: cellWidth, height: cellHeight)
    let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -gap * 0.15), blur: gap * 0.5,
                      color: CGColor(gray: 0, alpha: 0.12))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(image, in: frame)
    context.restoreGState()
}

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print(output.path(percentEncoded: false))

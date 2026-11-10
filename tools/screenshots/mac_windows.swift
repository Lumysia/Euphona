// Lists the on-screen windows of an app as "<window id> <width>x<height> <title>", for `screencapture -l`.
// Usage: swift tools/screenshots/mac_windows.swift Euphona
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Euphona"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == owner {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
    let title = window[kCGWindowName as String] as? String ?? ""
    print("\(id) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0)) \(title)")
}

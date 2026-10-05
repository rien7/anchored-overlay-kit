import AppKit
import Foundation

// Inspect the compositor screenshot, rather than CALayer.render (which does not
// reproduce UIKit's native per-corner geometry). Coordinates are AX screen points.
let arguments = CommandLine.arguments
guard arguments.count == 5,
      let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: arguments[1]))),
      let x = Double(arguments[2]), let y = Double(arguments[3]), let screenWidth = Double(arguments[4]) else {
  fatalError("Expected screenshot, panel x, panel y, screen width")
}
let scale = Double(bitmap.pixelsWide) / screenWidth
func blue(_ dx: Double, _ dy: Double) -> Bool {
  guard let color = bitmap.colorAt(x: Int((x + dx) * scale), y: Int((y + dy) * scale))?.usingColorSpace(.deviceRGB) else { return false }
  return color.redComponent < 0.16 && color.greenComponent > 0.3
    && color.greenComponent < 0.8 && color.blueComponent > 0.85
}
var count = 0
// The demo's top radius is 24pt. A cell's straight 2pt border cannot paint
// this interior region; only the library's curved boundary stroke reaches it.
for row in Int(3 * scale)..<Int(21 * scale) {
  for column in Int(3 * scale)..<Int(21 * scale) {
    if blue(Double(column) / scale, Double(row) / scale) { count += 1 }
  }
}
guard count > Int(10 * scale), !blue(1, 1) else {
  fatalError("Missing curved boundary or unclipped outer corner: \(count) blue pixels")
}
print("Curved selection boundary verified: \(count) blue pixels, outer corner clear")

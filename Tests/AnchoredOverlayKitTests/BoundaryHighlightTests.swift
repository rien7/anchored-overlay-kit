import XCTest
import UIKit
@testable import AnchoredOverlayKit

@MainActor final class BoundaryHighlightTests: XCTestCase {
  private final class Content: UIView, OverlayBoundaryHighlighting {
    var overlayBoundaryHighlights: [OverlayBoundaryHighlight] = []
  }

  @MainActor private final class Fixture {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    let panel = UIView(frame: CGRect(x: 20, y: 20, width: 200, height: 200))
    let content = Content(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    let tile = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let renderer = OverlayBoundaryRenderer(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    var radii = OverlayRadii(top: 40, bottomLeft: 24, bottomRight: 32)
    init() {
      window.addSubview(panel)
      panel.addSubview(content)
      content.addSubview(scroll)
      scroll.contentInsetAdjustmentBehavior = .never
      scroll.addSubview(tile)
      panel.addSubview(renderer)
      scroll.contentSize = CGSize(width: 200, height: 600)
      content.overlayBoundaryHighlights = [OverlayBoundaryHighlight(view: tile, clippedTo: scroll, color: .red, lineWidth: 4)]
    }
    func update() { renderer.update(content: content, panel: panel, radii: radii) }
    func image() -> UIImage {
      renderer.layoutIfNeeded()
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      return UIGraphicsImageRenderer(size: renderer.bounds.size, format: format).image { context in
        renderer.layer.render(in: context.cgContext)
      }
    }
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
      let image = image().cgImage!
      var pixel = [UInt8](repeating: 0, count: 4)
      let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return pixel
    }
    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixel(x, y)[3] }
  }

  func testOnlySelectedPanelBoundaryIsPainted() async {
    let f = Fixture()
    f.update()
    let attachment = XCTAttachment(image: f.image())
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertGreaterThan(f.alpha(60, 1), 200)
    XCTAssertEqual(f.alpha(140, 1), 0, "Unselected region must remain clear")
    XCTAssertEqual(f.alpha(50, 50), 0, "This API must not fill the selected content")
    // CALayer.render does not reproduce UIKit's per-corner compositor geometry.
    // Native curved edges are checked by the screenshot acceptance; the path
    // fallback is rasterizable here on older runtimes.
    if #unavailable(iOS 26.0) { XCTAssertEqual(f.alpha(0, 0), 0) }
    XCTAssertGreaterThan(f.alpha(1, 60), 200)
  }

  func testSelectionAndReuseClearStationaryRenderer() async {
    let f = Fixture()
    f.update()
    XCTAssertGreaterThan(f.alpha(60, 1), 200)
    f.content.overlayBoundaryHighlights = []
    f.update()
    XCTAssertEqual(f.alpha(60, 1), 0)
    f.content.overlayBoundaryHighlights = [OverlayBoundaryHighlight(view: f.tile)]
    f.tile.removeFromSuperview()
    f.update()
    XCTAssertEqual(f.renderer.subviews.count, 0)
  }

  func testScrollTracksCoverageWithoutCreatingViewportBorder() async {
    let f = Fixture()
    f.update()
    XCTAssertGreaterThan(f.alpha(1, 60), 200)
    f.scroll.contentOffset.y = 80
    f.update()
    XCTAssertEqual(f.alpha(1, 60), 0, "Offscreen selection must not leave an edge")
    f.scroll.frame.origin.y = 20
    f.scroll.contentOffset = .zero
    f.update()
    XCTAssertEqual(f.alpha(60, 1), 0)
    XCTAssertEqual(f.alpha(60, 20), 0, "Viewport clipping must not create a horizontal stroke")
    XCTAssertGreaterThan(f.alpha(1, 60), 200)
  }

  func testTransformAndRoundedRegionAreRespected() async {
    let f = Fixture()
    f.radii = OverlayRadii(top: 0, bottomLeft: 0, bottomRight: 0)
    f.content.overlayBoundaryHighlights = [OverlayBoundaryHighlight(view: f.tile, shape: .roundedRect(radius: 20))]
    f.update()
    XCTAssertEqual(f.alpha(0, 0), 0)
    XCTAssertGreaterThan(f.alpha(40, 1), 200)
    f.tile.transform = CGAffineTransform(translationX: 100, y: 0)
    f.update()
    XCTAssertEqual(f.alpha(40, 1), 0)
    XCTAssertGreaterThan(f.alpha(140, 1), 200)
  }

  func testHiddenAndInvalidTargetsAreIgnored() async {
    let f = Fixture()
    f.scroll.isHidden = true
    f.update()
    XCTAssertEqual(f.renderer.subviews.count, 0)
    f.scroll.isHidden = false
    f.content.overlayBoundaryHighlights[0].lineWidth = .nan
    f.update()
    XCTAssertEqual(f.renderer.subviews.count, 0)
    f.content.overlayBoundaryHighlights[0].lineWidth = 2
    let unrelated = UIView()
    f.content.overlayBoundaryHighlights[0].clippedTo = unrelated
    f.update()
    XCTAssertEqual(f.renderer.subviews.count, 0)
  }

  func testContentScalingDoesNotScaleStrokeWidth() async {
    let f = Fixture()
    f.radii = OverlayRadii(top: 0, bottomLeft: 0, bottomRight: 0)
    f.tile.frame = f.content.bounds
    f.content.layer.anchorPoint = .zero
    f.content.layer.position = .zero
    f.content.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    f.update()
    XCTAssertGreaterThan(f.alpha(60, 3), 200, "Width stays four panel points")
    XCTAssertEqual(f.alpha(60, 5), 0)
    XCTAssertEqual(f.alpha(140, 1), 0, "Coverage follows the scaled content")
  }

  func testDynamicColorTracksTargetTraits() async {
    let f = Fixture()
    f.content.overlayBoundaryHighlights[0].color = UIColor { traits in
      traits.userInterfaceStyle == .dark ? .blue : .red
    }
    f.tile.overrideUserInterfaceStyle = .light
    f.tile.updateTraitsIfNeeded()
    f.update()
    XCTAssertGreaterThan(f.pixel(60, 1)[0], 200)
    f.tile.overrideUserInterfaceStyle = .dark
    f.tile.updateTraitsIfNeeded()
    f.update()
    XCTAssertGreaterThan(f.pixel(60, 1)[2], 200)
    XCTAssertEqual(f.pixel(60, 1)[0], 0)
  }

  func testDescriptorsDoNotRetainReusableViews() async {
    var target: UIView? = UIView()
    let highlight = OverlayBoundaryHighlight(view: target!)
    target = nil
    XCTAssertNil(highlight.view)
  }

  func testGeometryChangesAndAsymmetricBottomCorners() async throws {
    let f = Fixture()
    f.tile.frame = f.content.bounds
    f.update()
    XCTAssertGreaterThan(f.alpha(100, 198), 200)
    if #available(iOS 26.0, *) {
      let outline = try XCTUnwrap(f.renderer.subviews.first?.subviews.first)
      XCTAssertEqual(outline.effectiveRadius(corner: .bottomLeft), 24)
      XCTAssertEqual(outline.effectiveRadius(corner: .bottomRight), 32)
    } else { XCTAssertEqual(f.alpha(0, 199), 0) }
    f.radii = OverlayRadii(top: 0, bottomLeft: 0, bottomRight: 32)
    f.update()
    XCTAssertGreaterThan(f.alpha(0, 199), 200)
    if #available(iOS 26.0, *) {
      let outline = try XCTUnwrap(f.renderer.subviews.first?.subviews.first)
      XCTAssertEqual(outline.effectiveRadius(corner: .bottomLeft), 0)
      XCTAssertEqual(outline.effectiveRadius(corner: .bottomRight), 32)
    } else { XCTAssertEqual(f.alpha(199, 199), 0) }
  }
}

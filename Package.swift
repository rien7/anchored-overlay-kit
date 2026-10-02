// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "AnchoredOverlayKit",
  platforms: [.iOS(.v16)],
  products: [.library(name: "AnchoredOverlayKit", targets: ["AnchoredOverlayKit"])],
  targets: [.target(name: "AnchoredOverlayKit")]
)

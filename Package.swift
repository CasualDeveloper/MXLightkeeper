// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MXLightkeeper",
  platforms: [
    .macOS("26.0"),
  ],
  products: [
    .library(
      name: "MXLightkeeperCore",
      targets: ["MXLightkeeperCore"]
    ),
  ],
  targets: [
    .target(
      name: "MXLightkeeperCore"
    ),
    .testTarget(
      name: "MXLightkeeperCoreTests",
      dependencies: ["MXLightkeeperCore"]
    ),
  ]
)

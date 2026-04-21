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
    .executable(
      name: "MXLightkeeperApp",
      targets: ["MXLightkeeperApp"]
    ),
  ],
  targets: [
    .target(
      name: "MXLightkeeperCore"
    ),
    .executableTarget(
      name: "MXLightkeeperApp",
      dependencies: ["MXLightkeeperCore"]
    ),
    .testTarget(
      name: "MXLightkeeperCoreTests",
      dependencies: ["MXLightkeeperCore"]
    ),
  ]
)

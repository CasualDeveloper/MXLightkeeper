// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MXLightkeeper",
  defaultLocalization: "en",
  platforms: [
    .macOS("15.0"),
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
    .executable(
      name: "mxlightkeeper",
      targets: ["mxlightkeeper"]
    ),
  ],
  targets: [
    .target(
      name: "MXLightkeeperCore"
    ),
    .executableTarget(
      name: "MXLightkeeperApp",
      dependencies: ["MXLightkeeperCore"],
      resources: [
        .process("Resources"),
      ]
    ),
    .executableTarget(
      name: "mxlightkeeper",
      dependencies: ["MXLightkeeperCore"]
    ),
    .testTarget(
      name: "MXLightkeeperCoreTests",
      dependencies: ["MXLightkeeperCore"]
    ),
    .testTarget(
      name: "MXLightkeeperAppTests",
      dependencies: ["MXLightkeeperApp"]
    ),
    .testTarget(
      name: "MXLightkeeperCLITests",
      dependencies: ["mxlightkeeper"]
    ),
  ]
)

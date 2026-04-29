// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "AbsorbPlayerCore",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "AbsorbPlayerCore",
      targets: ["AbsorbPlayerCore"]
    )
  ],
  targets: [
    .target(
      name: "AbsorbPlayerCore"
    )
  ]
)

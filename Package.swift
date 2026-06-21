// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CodexCopilotUsageBar",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "TokenBar", targets: ["CodexCopilotUsageBar"])
  ],
  targets: [
    .executableTarget(name: "CodexCopilotUsageBar")
  ]
)

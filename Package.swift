// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PharmacyCore", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "PharmacyCore", targets: ["PharmacyCore"])], targets: [.target(name: "PharmacyCore"), .testTarget(name: "PharmacyCoreTests", dependencies: ["PharmacyCore"])])

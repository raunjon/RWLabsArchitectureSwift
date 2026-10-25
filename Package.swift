// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "RWLabsArchitecture",
    platforms: [
           .iOS(.v17),
           .macOS(.v10_15)
       ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RWLabsArchitecture",
            targets: ["RWLabsArchitecture"]
        ),
    ],
    dependencies: [
        .package(url:"https://github.com/pointfreeco/swift-case-paths.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"700.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .macro(
            name: "RWLabsArchitectureMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "RWLabsArchitecture",
            dependencies: [
                "RWLabsArchitectureMacros",
                .product(name: "CasePaths", package: "swift-case-paths") // 🔥 REQUIRED
            ]
        ),
        .testTarget(
            name: "RWLabsArchitectureTests",
            dependencies: ["RWLabsArchitecture", .product(name: "CasePaths", package: "swift-case-paths")]
        ),
    ]
)

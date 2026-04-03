// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
        .package(path: "../RWLabsDataServiceKit"),
        .package(url:"https://github.com/pointfreeco/swift-case-paths.git", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RWLabsArchitecture",
            dependencies: ["RWLabsDataServiceKit",.product(name: "CasePaths", package: "swift-case-paths") // 🔥 REQUIRED
]
        ),

    ]
)

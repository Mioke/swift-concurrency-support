// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-concurrency-support",
    products: [
      // Products define the executables and libraries a package produces, making them visible to other packages.
      .library(
        name: "SwiftConcurrencySupport",
        targets: ["swift-concurrency-support"]),
    ], 
    dependencies: [
      .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "6.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-concurrency-support"),
        .testTarget(
            name: "swift-concurrency-supportTests",
            dependencies: [
              "swift-concurrency-support",
              .product(name: "RxCocoa", package: "RxSwift")
            ]),
    ]
)

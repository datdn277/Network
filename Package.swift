// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NetworkClientKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "NetworkClientInterface", targets: ["NetworkClientInterface"]),
        .library(name: "NetworkClientOpenAPI", targets: ["NetworkClientOpenAPI"]),
        .library(name: "NetworkClientKit", targets: ["NetworkClientKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0")
    ],
    targets: [
        .target(name: "NetworkClientInterface"),
        .target(
            name: "NetworkClientOpenAPI",
            dependencies: ["NetworkClientInterface"]
        ),
        .target(
            name: "NetworkClientKit",
            dependencies: [
                "NetworkClientInterface",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .testTarget(name: "NetworkClientInterfaceTests", dependencies: ["NetworkClientInterface"]),
        .testTarget(
            name: "NetworkClientOpenAPITests",
            dependencies: [
                "NetworkClientKit",
                "NetworkClientOpenAPI"
            ]
        ),
        .testTarget(
            name: "NetworkClientKitTests",
            dependencies: [
                "NetworkClientKit",
                "NetworkClientInterface",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        )
    ]
)

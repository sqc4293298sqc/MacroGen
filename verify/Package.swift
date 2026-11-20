// swift-tools-version: 6.1
// 真 3D CAM 运行验证：只在 CI 里跑 OCCT 建模 + 刀路生成，不产出 IPA。
// 本目录不是 App target，不参与 iOS 打包。
import PackageDescription

let package = Package(
    name: "CAMVerify",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CAMVerify",
            dependencies: [
                .product(name: "OCCTSwift", package: "OCCTSwift")
            ],
            path: "Sources/CAMVerify"
        )
    ]
)

// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DragWheel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DragWheel",
            path: "Sources/DragWheel",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)

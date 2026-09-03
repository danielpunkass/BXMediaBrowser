// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(

    name: "BXMediaBrowser",
    defaultLocalization: "en",
    
    // Deployment targets for each supported platform
    
    platforms:
    [
		.macOS("14.0"),		// Must match MACOSX_DEPLOYMENT_TARGET in BXMediaBrowser.xcconfig
		.iOS("14.0")		// First version that has UniformTypeIdentifiers (UTType)
    ],
    
	// Products define the executables and libraries a package produces, and make them visible to other packages

    products:
    [
        .library(name:"BXMediaBrowser", targets:["BXMediaBrowser"]),
    ],
    
	// Dependencies declare other packages that this package depends on

    dependencies:
    [
        .package(url:"https://github.com/danielpunkass/BXSwiftUtils.git", .branch("marsedit")),
        .package(url:"https://github.com/danielpunkass/BXSwiftUI.git", .branch("marsedit")),
        .package(url:"https://github.com/peterb180369/OAuth2.git", .revision("1a617f1feb4d72e9cc7ec0afa3df0e94cd57431d")),
    ],
    
	// Targets are the basic building blocks of a package. A target can define a module or a test suite.
	// Targets can depend on other targets in this package, and on products in packages this package depends on.

    targets:
    [
        .target(name:"BXMediaBrowser", dependencies:["BXSwiftUtils","BXSwiftUI","OAuth2"], resources:[.process("Resources")], swiftSettings:
        [
            // MarsEdit builds its own iMedia.framework alongside this package during the transition away from it,
            // which makes canImport(iMedia) true. The Lightroom Classic sources expect Boinx's iMedia binary, so
            // keep them out of the build entirely.
            .define("BXMEDIABROWSER_EXCLUDE_LIGHTROOM_CLASSIC"),
        ]),
        .testTarget(name:"BXMediaBrowserTests", dependencies:["BXMediaBrowser"]),
    ]
)

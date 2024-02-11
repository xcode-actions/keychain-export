// swift-tools-version: 5.9
import PackageDescription


let package = Package(
	name: "keychain-export",
	platforms: [.macOS(.v11)],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
		.package(url: "https://github.com/apple/swift-log.git",             from: "1.5.4"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git",    from: "0.8.0"),
	],
	targets: [
		.executableTarget(
			name: "keychain-export",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "CLTLogger",      package: "clt-logger"),
				.product(name: "Logging",        package: "swift-log"),
			]
		),
	]
)

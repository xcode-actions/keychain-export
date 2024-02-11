// swift-tools-version: 5.9
import PackageDescription


let package = Package(
	name: "keychain-export",
	platforms: [.macOS(.v12)],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git",            from: "1.3.0"),
		.package(url: "https://github.com/apple/swift-log.git",                        from: "1.5.4"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git",               from: "0.8.0"),
		.package(url: "https://github.com/xcode-actions/swift-process-invocation.git", from: "1.0.0"),
	],
	targets: [
		.executableTarget(
			name: "keychain-export",
			dependencies: [
				.product(name: "ArgumentParser",    package: "swift-argument-parser"),
				.product(name: "CLTLogger",         package: "clt-logger"),
				.product(name: "Logging",           package: "swift-log"),
				.product(name: "ProcessInvocation", package: "swift-process-invocation"),
			]
		),
	]
)

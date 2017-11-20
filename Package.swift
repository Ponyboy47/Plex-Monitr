// swift-tools-version:4.0

import PackageDescription

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/Ponyboy47/Async.git", .upToNextMinor(from: "3.1.0")),
    .package(url: "https://github.com/IBM-Swift/BlueSignals.git", .upToNextMajor(from: "0.9.50")),
    .package(url: "https://github.com/Ponyboy47/CLI.git", .upToNextMinor(from: "2.0.1")),
    .package(url: "https://github.com/Ponyboy47/Cron-Swift.git", .upToNextMajor(from: "2.1.0")),
    .package(url: "https://github.com/Ponyboy47/Downpour.git", .upToNextMinor(from: "0.5.0")),
    .package(url: "https://github.com/Ponyboy47/Duration.git", .upToNextMinor(from: "3.1.0")),
    .package(url: "https://github.com/Ponyboy47/PathKit.git", .upToNextMajor(from: "0.9.0")),
    .package(url: "https://github.com/Ponyboy47/Strings.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/kareman/SwiftShell.git", .upToNextMinor(from: "4.0.0")),
    .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMinor(from: "1.4.0"))
]
var namedDependencies: [Target.Dependency] = ["Async", "Signals", "CLI", "Cron", "Downpour", "Duration", "PathKit", "Strings", "SwiftShell", "SwiftyBeaver"]

#if os(Linux)
dependencies.append(.package(url: "https://github.com/Ponyboy47/inotify.git", .upToNextMinor(from: "0.4.1")))
namedDependencies.append("Inotify")
#endif

let package = Package(
    name: "Plex-Monitr",
    products: [
        .executable(
            name: "monitr",
            targets: ["monitr"])
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "monitr",
            dependencies: namedDependencies)
    ]
)

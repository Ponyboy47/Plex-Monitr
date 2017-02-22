import PackageDescription

let package = Package(
    name: "monitr",
    dependencies: [
        .Package(url: "https://github.com/ponyboy47/PathKit.git", majorVersion: 0, minor: 8),
        .Package(url: "https://github.com/vdka/JSON", majorVersion: 0, minor: 16),
        .Package(url: "https://github.com/oarrabi/Guaka.git", majorVersion: 0, minor: 1),
        .Package(url: "https://github.com/TryFetch/Downpour.git", majorVersion: 0, minor: 2),
        .Package(url: "https://github.com/duemunk/Async.git", majorVersion: 2, minor: 0),
        .Package(url: "https://github.com/IBM-Swift/BlueSignals.git", majorVersion: 0, minor: 9)
    ],
    exclude: [
        "Tests"
    ]
)

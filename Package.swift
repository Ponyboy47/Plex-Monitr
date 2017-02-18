import PackageDescription

let package = Package(
    name: "monitr",
    dependencies: [
        .Package(url: "https://github.com/ponyboy47/PathKit.git", majorVersion: 0, minor: 8),
        .Package(url: "https://github.com/vdka/JSON", majorVersion: 0, minor: 16),
        .Package(url: "https://github.com/ponyboy47/Commander", majorVersion: 0, minor: 7),
        .Package(url: "https://github.com/andrew804/Regex.git", majorVersion: 0, minor: 4),
        .Package(url: "https://github.com/behrang/YamlSwift.git", majorVersion: 3, minor: 3),
        .Package(url: "https://github.com/TryFetch/Downpour.git", majorVersion: 0, minor: 2)
    ],
    exclude: [
        "Tests"
    ]
)

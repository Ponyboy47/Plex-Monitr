import PackageDescription

let package = Package(
    name: "monitr",
    dependencies: [
        .Package(url: "https://github.com/nvzqz/FileKit.git", majorVersion: 4, minor: 0),
        .Package(url: "https://github.com/vdka/JSON", majorVersion: 0, minor: 16),
        .Package(url: "https://github.com/kylef/Commander", majorVersion: 0, minor: 6),
        .Package(url: "https://github.com/crossroadlabs/Regex.git", majorVersion: 0),
        .Package(url: "https://github.com/behrang/YamlSwift.git", majorVersion: 3, minor: 3),
        .Package(url: "https://github.com/tadija/AEXML.git", majorVersion: 4)
    ]
)

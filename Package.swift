import PackageDescription

var dependencies: [Package.Dependency] = [
        .Package(url: "https://github.com/Ponyboy47/PathKit.git", majorVersion: 0, minor: 8),
        // Downpour requires vdka/JSON so I don't need it's dependency here
        .Package(url: "https://github.com/Ponyboy47/Downpour.git", majorVersion: 0, minor: 3),
        .Package(url: "https://github.com/IBM-Swift/BlueSignals.git", majorVersion: 0, minor: 9)
]

//#if !os(Linux)
dependencies.append(.Package(url: "https://github.com/Ponyboy47/Async.git", majorVersion: 2))
//#endif

let package = Package(
    name: "monitr",
    dependencies: dependencies,
    exclude: [
        "Tests"
    ]
)

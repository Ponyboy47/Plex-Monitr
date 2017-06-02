import PackageDescription

var dependencies: [Package.Dependency] = [
    .Package(url: "https://github.com/Ponyboy47/PathKit.git", majorVersion: 0, minor: 8),
    .Package(url: "https://github.com/Ponyboy47/Strings.git", majorVersion: 1),
    .Package(url: "https://github.com/Ponyboy47/CLI.git", majorVersion: 1),
    // My Downpour fork requires vdka/JSON so I don't need it's dependency here
    .Package(url: "https://github.com/Ponyboy47/Downpour.git", majorVersion: 0, minor: 4),
    .Package(url: "https://github.com/IBM-Swift/BlueSignals.git", majorVersion: 0, minor: 9),
    .Package(url: "https://github.com/Ponyboy47/Async.git", majorVersion: 2),
    .Package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", majorVersion: 1),
    .Package(url: "https://github.com/Ponyboy47/Duration.git", majorVersion: 2),
    .Package(url: "https://github.com/Ponyboy47/UUID.git", majorVersion: 0, minor: 8),
    .Package(url: "https://github.com/Ponyboy47/Cron-Swift.git", majorVersion: 1)
]

var targets: [Target] = []
var swiftDependencies: [Target.Dependency] = []
var excludes: [String] = ["Tests"]

#if os(Linux)
// On linux we need to include the inotify C module, and the C functions from select
dependencies.append(.Package(url: "https://github.com/Ponyboy47/inotify.git", majorVersion: 1))
targets.append(Target(name: "CSelect"))
swiftDependencies.append("CSelect")
#else
// On osX/iOS/watchOS/tvOS ignore the C funtions in select
excludes.append("Sources/CSelect")
// Importing this package through both Downpour and here causes issues with multiple libraries found on linux
dependencies.append(.Package(url: "https://github.com/vdka/JSON", majorVersion: 0))
#endif

// The monitr directory is always required
targets.append(Target(name: "monitr", dependencies: swiftDependencies))

let package = Package(
    name: "monitr",
    targets: targets,
    dependencies: dependencies,
    exclude: excludes
)

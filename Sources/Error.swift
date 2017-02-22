import Foundation

enum MonitrError: Swift.Error {
}

enum ConfigError: Swift.Error {
    case pathIsNotDirectory
    case pathDoesNotExist
}

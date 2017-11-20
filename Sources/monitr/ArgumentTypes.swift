//
//  CLI.swift
//  monitr
//
//  Created by Jacob Williams on 6/1/17.
//
//

import CLI
import PathKit
import Cron

extension Path: ArgumentType {
    public static func from(string value: String) throws -> Path {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        return Path(value)
    }
}

extension DatePattern: ArgumentType, Equatable {
    public static func from(string value: String) throws -> DatePattern {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let pattern = try? DatePattern(value) else {
            throw ConfigError.invalidCronString(value)
        }
        return pattern
    }

    public static func ==(lhs: DatePattern, rhs: DatePattern) -> Bool {
        return lhs.string == rhs.string
    }
}

/// Allows VideoContainers to be used as cli arguments
extension VideoContainer: ArgumentType {
    static func from(string value: String) throws -> VideoContainer {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let vc = VideoContainer(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid VideoContainer")
        }
        return vc
    }
}

/// Allows VideoCodec namess to be used as cli arguments
extension VideoCodec: ArgumentType {
    static func from(string value: String) throws -> VideoCodec {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let vc = VideoCodec(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid VideoCodec.CodecName")
        }
        return vc
    }
}

/// Allows AudioContainers to be used as cli arguments
extension AudioContainer: ArgumentType {
    static func from(string value: String) throws -> AudioContainer {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let ac = AudioContainer(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid AudioContainer")
        }
        return ac
    }
}

/// Allows AudioCodec names to be used as cli arguments
extension AudioCodec: ArgumentType {
    static func from(string value: String) throws -> AudioCodec {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let ac = AudioCodec(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid AudioCodec.CodecName")
        }
        return ac
    }
}

/// Allows Languages to be used as cli arguments
extension Language: ArgumentType {
    static func from(string value: String) throws -> Language {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let lang = Language(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid Language")
        }
        return lang
    }
}

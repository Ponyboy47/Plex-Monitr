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
import SwiftyBeaver

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

    public static func == (lhs: DatePattern, rhs: DatePattern) -> Bool {
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

/// Allows transcode_video --target option to be used as a cli argument in Monitr
extension Target: ArgumentType {
    static func from(string value: String) throws -> Target {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let target = Target(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid Target")
        }
        return target
    }
}

/// Allow transcode_video speed presets to be used as a cli argument through Monitr
extension TranscodeSpeed: ArgumentType {
    static func from(string value: String) throws -> TranscodeSpeed {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let speed = TranscodeSpeed(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid TranscodeSpeed")
        }
        return speed
    }
}

/// Allow x264 speed presets to be used as a cli argument through Monitr
extension X264Preset: ArgumentType {
    static func from(string value: String) throws -> X264Preset {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let preset = X264Preset(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid X264Preset")
        }
        return preset
    }
}

/// Allows SwiftyBeaver log levels to be used as a cli argument in Monitr
extension SwiftyBeaver.Level: ArgumentType, Comparable {
    private enum _Level: String {
        case verbose
        case debug
        case info
        case warning
        case warn
        case error
    }

    public static func from(string value: String) throws -> SwiftyBeaver.Level {
        guard value.count > 0 else {
            throw ArgumentError.emptyString
        }
        if let intValue = Int(value) {
            guard let level = SwiftyBeaver.Level(rawValue: intValue) else {
                throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid SwiftyBeaver.Level")
            }
            return level
        }

        guard let level = _Level(rawValue: value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to a valid SwiftyBeaver.Level")
        }
        switch level {
        case .verbose: return .verbose
        case .debug: return .debug
        case .info: return .info
        case .warn, .warning: return .warning
        case .error: return .error
        }
    }

    public static func == (lhs: SwiftyBeaver.Level, rhs: SwiftyBeaver.Level) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    public static func == (lhs: SwiftyBeaver.Level, rhs: Int) -> Bool {
        return lhs.rawValue == rhs
    }
    public static func == (lhs: Int, rhs: SwiftyBeaver.Level) -> Bool {
        return lhs == rhs.rawValue
    }

    public static func < (lhs: SwiftyBeaver.Level, rhs: SwiftyBeaver.Level) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    public static func < (lhs: SwiftyBeaver.Level, rhs: Int) -> Bool {
        return lhs.rawValue < rhs
    }
    public static func < (lhs: Int, rhs: SwiftyBeaver.Level) -> Bool {
        return lhs < rhs.rawValue
    }
}

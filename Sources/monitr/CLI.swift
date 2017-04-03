/*

    CLI.swift

    Created By: Jacob Williams
    Description: This file contains a parser for argc/argv and retrieves CLI arguments
    License: MIT License

*/

import Foundation
import PathKit
import Async

/// Errors that occur in the CLI
enum ArgumentError: Error {
    case conversionError(String)
    case emptyString
    case requiredArgumentNotSet(String)
    case invalidShortName(String)
    case invalidLongName(String)
}

/// Protocol for types to be usable in Arguments on the command line. Types
///   must be able to be retrieved from a string, since that is what the CLI sends
protocol ArgumentType {
    static func from(string value: String) throws -> Self
}

/// Protocol for CLI arguments
protocol Argument {
    associatedtype ArgType: ArgumentType
    /// The single character identifier for the cli argument
    var shortName: Character { get set }
    /// The long identifier for the cli argument
    var longName: String? { get set }
    /// The default value for the cli argument
    var `default`: ArgType? { get set }
    /// The description of the cli argument
    var description: String? { get set }
    /// The usage string for cli argument
    var usage: String { get }
    /// Whether or not the argument is required to be set
    var `required`: Bool { get set }
    /// The type of the argument value
    var type: ArgType.Type { get }
    var usageDescriptionActualLength: Int { get set }
    var usageDescriptionNiceLength: Int { get set }

    /**
     Initializer

     - Parameter shortName: The single character identifier for the cli argument
     - Parameter longName: The long identifier for the cli argument
     - Parameter default: The default value for the cli argument
     - Parameter description: The usage description for the cli argument
     - Parameter required: Whether or not the argument is required to be set
    */
    init(_ shortName: Character, longName: String?, `default`: ArgType?, description: String?, `required`: Bool, parser: ArgumentParser?) throws
    /// Parses the cli arguments to get the string value of the argument, or nil if it is not set
    func parse() throws -> ArgType?
    /// Returns the argument's value, it's default value if that is nil, or throws an error if it's required but the value is nil
    func getValue(from: String) throws -> ArgType?
}

/// CLI Arguments that come with a value
final class Option<A: ArgumentType>: Argument {
    typealias ArgType = A
    var shortName: Character
    var longName: String?
    var `default`: ArgType?
    var description: String?
    var `required`: Bool
    var type: ArgType.Type {
        return ArgType.self
    }
    var usage: String {
        var u = "\t-\(shortName)"
        if let l = longName {
            u += ", --\(l)"
        }
        usageDescriptionActualLength = u.characters.count

        while u.characters.count < usageDescriptionNiceLength {
            u += " "
        }

        if let d = description {
            u += ": \(d)"
        }
        if let d = `default` {
            u += "\n\t"
            for _ in 0...usageDescriptionNiceLength {
                u += " "
            }
            u += "DEFAULT: \(d)"
        }
        return u
    }
    var usageDescriptionActualLength: Int = 0
    var usageDescriptionNiceLength: Int = 0

    required init(_ shortName: Character, longName: String? = nil, `default`: ArgType? = nil, description: String? = nil, `required`: Bool = false, parser: ArgumentParser? = nil) throws {
        guard shortName != "h" else {
            throw ArgumentError.invalidShortName("Cannot use 'h' as the short name since it is reserved for help/usage text.")
        }
        self.shortName = shortName
        if let l = longName {
            guard l != "help" else {
                throw ArgumentError.invalidLongName("Cannot use 'help' as the long name since it is reserved for help/usage text.")
            }
        }
        self.longName = longName
        self.`default` = `default`
        self.description = description
        self.`required` = `required`

        parser?.arguments.append(self)
    }

    func parse() throws -> ArgType? {
        // Try and get the string value of the argument from the cli
        if let stringValue = ArgumentParser.parse(self) {
            // Try and convert that string value to the proper type
            return try getValue(from: stringValue)
        }

        // No string value specified in the cli, so try and return the default value
        if let value = `default` {
            return value
        // If the value is required and has no default value, throw an error
        } else if `required` {
            throw ArgumentError.requiredArgumentNotSet(longName ?? String(shortName))
        }

        // No value specified in the cli, no default value, not required, so return nil
        return nil
    }

    func getValue(from: String) throws -> ArgType? {
        // Try and convert the string value to the expected type, or use the default value
        do {
            return try ArgType.from(string: from)
        } catch {
            // If no value and it's required, throw an error
            if let value = `default` {
                return value
            } else if `required` {
                throw ArgumentError.requiredArgumentNotSet(longName ?? String(shortName))
            }
        }
        return nil
    }
}

/// CLI arguments that are true/false depending on whether or not they're present
typealias Flag = Option<Bool>

/// Allows Bools to be used as cli arguments
extension Bool: ArgumentType {
    static func from(string value: String) throws -> Bool {
        guard value.characters.count > 0 else {
            throw ArgumentError.emptyString
        }
        if value == "1" {
            return true
        } else if value == "0" {
            return false
        } else if let b = Bool(value) {
            return b
        }

        throw ArgumentError.conversionError("Cannot convert '\(value)' to '(Bool.self)'")
    }
}

/// Allows Ints to be used as cli arguments
extension Int: ArgumentType {
    static func from(string value: String) throws -> Int {
        guard value.characters.count > 0 else {
            throw ArgumentError.emptyString
        }
        guard let val = Int(value) else {
            throw ArgumentError.conversionError("Cannot convert '\(value)' to '\(Int.self)' ")
        }

        return val
    }
}

/// Allows Paths to be used as cli arguments
extension Path: ArgumentType {
    static func from(string value: String) throws -> Path {
        guard value.characters.count > 0 else {
            throw ArgumentError.emptyString
        }
        return Path(value)
    }
}

/// Parses the CLI for Arguments
final class ArgumentParser {
    var usage: String
    var arguments: [Any] = []

    required init(_ usage: String) {
        self.usage = usage
    }

    static var needsHelp: Bool = {
        var h: Bool = false
        do {
            if let help = ArgumentParser.parse(longName: "help", isBool: true) {
                h = try Bool.from(string: help)
            } else if let help = ArgumentParser.parse(shortName: "h", isBool: true) {
                h = try Bool.from(string: help)
            }
        } catch {
            print("An error occured determing if the help/usage text needed to be displayed.\n\t\(error)")
        }
        return h
    }()

    /// Parse for a specific Argument and returns it's string value if it finds one
    class func parse<A: Argument>(_ argument: A) -> String? {
        let isBool = argument.type is Bool.Type
        // If the argument has a long name, let's look for that first
        if let longName = argument.longName {
            // If the long name has a value...
            if let value = ArgumentParser.parse(longName: longName, isBool: isBool) {
        		// If the value is a bool or the argument has no default value,
		        //   then just return what we got
                guard isBool, let d = argument.`default` else { return value }

                // Otherwise return the opposite boolean of the default value
                return String(!(d as! Bool))
            }
        }

        // Now check to see if we find a short name value
        if let value = ArgumentParser.parse(shortName: argument.shortName, isBool: isBool) {
            // If the value is a bool or the argument has no default value,
            //   then just return what we got
            guard isBool, let d = argument.`default` else { return value }

            // Otherwise return the opposite boolean of the default value
            return String(!(d as! Bool))
        }

        // If we didn't find the cli argument, return nil
        return nil
    }

    /// Parse for a specific longName argument
    class func parse(longName: String, isBool: Bool = false) -> String? {
        // Drop the first argument since it's just the path to the executable
        let args = CommandLine.arguments.dropFirst()
        // Try and find the index of the long argument
        if let index = args.index(of: "--\(longName)"), index >= 0 {
            // If the argument we're looking for is a Bool, go ahead and return true
            guard !isBool else { return String(true) }
            // So try and get the string value of the next argument, then return it
            if let index = args.index(of: "--\(longName)"), args.count <= index + 1 {
                let next = args[index + 1]
                return next
            }
            // Otherwise, return nil
            return nil
        }
        return nil
    }

    /// Parse for a specific shortName argument
    class func parse(shortName: Character, isBool: Bool = false) -> String? {
        // Drop the first argument since it's just the path to the executable
        let args = CommandLine.arguments.dropFirst()
        // Go over all the flag arguments
        for arg in args.filter({ $0.starts(with: "-") && !$0.starts(with: "--") }) {
            // Get rid of the hyphen and return the remaining characters
            let argChars = arg.dropFirst().characters
            // Look for the argument in the array, else return nil
            guard let _ = argChars.index(of: shortName) else { continue }
            // Make sure it's not a bool, or else just return true
            guard !isBool else { return String(true) }
            // Get the index from the array of all args
            let index = args.index(of: arg)!
            // Try and return the next argument's string value
            return args[index + 1]
        }
        // Returns nil only when there were no arguments
        return nil
    }

    /// Prints the usage text for all of the arguments included in the parser
    func printHelp() {
        print("Usage: \(usage)\n\nOptions:")
        // Get the length of the longest usage description so that we can
        // format everything nicely
        var longest = 0
        for arg in arguments {
            if let flag = arg as? Flag {
                let _ = flag.usage
                longest = flag.usageDescriptionActualLength > longest ? flag.usageDescriptionActualLength : longest
            } else if let path = arg as? Option<Path> {
                let _ = path.usage
                longest = path.usageDescriptionActualLength > longest ? path.usageDescriptionActualLength : longest
            } else if let int = arg as? Option<Int> {
                let _ = int.usage
                longest = int.usageDescriptionActualLength > longest ? int.usageDescriptionActualLength : longest
            }
        }

        // Now do the actual printing of arguments' usage descriptions
        for arg in arguments {
            if let flag = arg as? Flag {
                flag.usageDescriptionNiceLength = longest + 4
                print(flag.usage)
            } else if let path = arg as? Option<Path> {
                path.usageDescriptionNiceLength = longest + 4
                print(path.usage)
            } else if let int = arg as? Option<Int> {
                int.usageDescriptionNiceLength = longest + 4
                print(int.usage)
            } else {
                continue
            }
        }
    }
}

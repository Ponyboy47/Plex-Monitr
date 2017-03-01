/*

    Guaka+Types.swift

    Created By: Jacob Williams
    Description: This file contains the extensions to Guaka to make Double and
                   Path types usable from the CLI
    License: MIT License

*/
import Guaka
import PathKit

extension Double: FlagValue {
    public static func fromString(flagValue value: String) throws -> Double {
        return Double(value) ?? 0.0
    }

    public static var typeDescription: String { return "double" }
}

extension Path: FlagValue {
    public static func fromString(flagValue value: String) throws -> Path {
        return Path(value)
    }

    public static var typeDescription: String { return "path" }
}

extension Flags {
    public func getDouble(name: String) -> Double? {
        return get(name: name, type: Double.self)
    }

    public func getPath(name: String) -> Path? {
        return get(name: name, type: Path.self)
    }
}

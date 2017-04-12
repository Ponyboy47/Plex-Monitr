import Foundation

enum TimeError: Error {
    case invalidNumberOfComponents
    case nonIntegerValue(String)
    case invalidHour(Int)
    case invalidMinute(Int)
}

struct Time {
    var hour: Int
    var minute: Int

    var string: String {
        return "\(hour):\(minute)"
    }

    init(_ str: String) throws {
        let parts = str.components(separatedBy: ":")
        guard parts.count <= 2 else {
            throw TimeError.invalidNumberOfComponents
        }

        guard let h = Int(parts[0]) else {
            throw TimeError.nonIntegerValue(parts[0])
        }
        guard h < 24 else {
            throw TimeError.invalidHour(h)
        }
        hour = h

        if parts.count == 2 {
            guard let m = Int(parts[1]) else {
                throw TimeError.nonIntegerValue(parts[1])
            }
            guard m < 60 else {
                throw TimeError.invalidMinute(m)
            }
            minute = m
        } else {
            minute = 0
        }
    }

    init(_ date: Date) {
        let calendar = Calendar.current

        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
}

extension Time: ExpressibleByStringLiteral {
    typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    typealias UnicodeScalarLiteralType = StringLiteralType

    init(extendedGraphemeClusterLiteral str: StringLiteralType) {
        do {
            try self.init(str)
        } catch {
            try! self.init("0:00")
        }
    }

    init(unicodeScalarLiteral str: StringLiteralType) {
        do {
            try self.init(str)
        } catch {
            try! self.init("0:00")
        }
    }

    init(stringLiteral str: StringLiteralType) {
        do {
            try self.init(str)
        } catch {
            try! self.init("0:00")
        }
    }
}

extension Time: CustomStringConvertible {
    var description: String {
        return string
    }
}

extension Time: Comparable {
    static func ==(lhs: Time, rhs: Time) -> Bool {
        return lhs.string == rhs.string
    }

    static func <(lhs: Time, rhs: Time) -> Bool {
        if lhs.hour != lhs.hour {
            return lhs.hour < rhs.hour
        } else {
            return lhs.minute < rhs.minute
        }
    }
}

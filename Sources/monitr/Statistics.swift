import PathKit
import Duration
import Cron
import Foundation

extension Array where Element == Double {
    func avg() -> Double? {
        guard self.count > 0 else { return nil }
        var total: Double = 0.0
        for d in self {
            total += d
        }
        return total / Double(self.count)
    }
}

extension Array where Element == Statistic.Event {
    func avg() -> Double? {
        return self.map({ $0.duration }).avg()
    }

    func min() -> Double? {
        return self.map({ $0.duration }).min()
    }

    func max() -> Double? {
        return self.map({ $0.duration }).max()
    }
}

enum StatisticsError: Error {
    case pathIsNotDirectory(Path)
}

enum Statistics: String {
    case startup
    case move
    case convert
    case lifespan
}

struct Statistic {
    struct Event {
        var start: Cron.Date = Cron.Date()
        var finish: Cron.Date?
        var duration: Double = 0.0
    }

    static let filename: Path = "statistics.json"

    // From the moment the executable is ran, to the first run on the monitr
    var shortestStartup: Double {
        return startups.min() ?? 0.0
    }
    var longestStartup: Double {
        return startups.max() ?? 0.0
    }
    var averageStartup: Double {
        return startups.avg() ?? 0.0
    }
    fileprivate var startups: [Event] = []

    // Moving media from the downloads directory to the plex directory
    var shortestMove: Double {
        return moves.min() ?? 0.0
    }
    var longestMove: Double {
        return moves.max() ?? 0.0
    }
    var averageMove: Double {
        return moves.avg() ?? 0.0
    }
    fileprivate var moves: [Event] = []

    // Converting a single media file
    var shortestConversion: Double {
        return conversions.min() ?? 0.0
    }
    var longestConversion: Double {
        return conversions.min() ?? 0.0
    }
    var averageConversion: Double {
        return conversions.avg() ?? 0.0
    }
    fileprivate var conversions: [Event] = []

    // The lifespan of the monitr application
    var shortestLife: Double {
        return lifespans.min() ?? 0.0
    }
    var longestLife: Double {
        return lifespans.max() ?? 0.0
    }
    var averageLife: Double {
        return lifespans.avg() ?? 0.0
    }
    fileprivate var lifespans: [Event] = []

    init() {
        Duration.pushLogStyle(style: .none)
    }

    public func measure(_ statKey: Statistics, _ block: MeasuredBlock) {
        var event = Event()
        event.duration = Duration.measure(UUID().description, block: block)
        event.finish = Cron.Date()

        var stat = keyMapper(statKey)
        stat.append(event)
    }

    private func keyMapper(_ key: Statistics) -> [Event] {
        switch key {
        case .startup:
            return startups
        case .move:
            return moves
        case .convert:
            return conversions
        case .lifespan:
            return lifespans
        }
    }
}

extension Cron.Date: JSONConvertible {
    public init(json: JSON) throws {
        year = try json.get("year")
        month = try json.get("month")
        day = try json.get("day")
        hour = try json.get("hour")
        minute = try json.get("minute")
        second = try json.get("second")
    }

    public func encoded() -> JSON {
        return [
            "year": year,
            "month": month,
            "day": day,
            "hour": hour,
            "minute": minute,
            "second": second
        ]
    }
}

extension Statistic.Event: JSONConvertible {
    init(json: JSON) throws {
        start = try json.get("start")
        finish = try? json.get("finish")
        duration = (try? json.get("duration")) ?? 0.0
    }

    func encoded() -> JSON {
        var json: JSON = [
            "start": start,
            "duration": duration
        ]
        if let f = finish {
            json["finish"] = f.encoded()
        }
        return json
    }
}

extension Statistic: JSONConvertible {
    init(_ path: Path) throws {
        try self.init(path.read())
    }

    init(_ str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    init(json: JSON) throws {
        startups = try json.get("startups")
        moves = try json.get("moves")
        conversions = try json.get("conversions")
        lifespans = try json.get("lifespans")
    }

    func encoded() -> JSON {
        return [
            "startups": startups.encoded(),
            "moves": moves.encoded(),
            "conversions": conversions.encoded(),
            "lifespans": lifespans.encoded()
        ]
    }

    func serialized() throws -> String {
        return try encoded().serialized()
    }

    func save(_ dir: Path) throws {
        if !dir.exists {
            try dir.mkpath()
        }

        guard dir.isDirectory else {
            throw StatisticsError.pathIsNotDirectory(dir)
        }

        let statisticsPath = dir + Statistic.filename
        try statisticsPath.write(self.serialized(), force: true)
    }
}

import PathKit
import Async
import SwiftyBeaver
import Cron
import JSON

enum ConversionError: Error {
    case maxThreadsReached
    case noJobsLeft
    case noJobIndex
}

class ConversionQueue: JSONInitializable, JSONRepresentable {
    static let filename: String = "conversionqueue.json"

    fileprivate var configPath: Path
    fileprivate var cronStart: CronJob
    fileprivate var cronEnd: CronJob
    fileprivate var statistics: Statistic
    fileprivate var conversionGroup: AsyncGroup = AsyncGroup()
    fileprivate var maxThreads: Int
    fileprivate var deleteOriginal: Bool
    fileprivate var log: SwiftyBeaver.Type
    fileprivate var videoConversionConfig: VideoConversionConfig
    fileprivate var audioConversionConfig: AudioConversionConfig

    fileprivate var jobs: [BaseConvertibleMedia] = []
    fileprivate var activeJobs: [BaseConvertibleMedia] = []

    var active: Int {
        return activeJobs.count
    }

    init(_ config: Config, statistics stats: Statistic? = nil) {
        configPath = config.configFile
        // Ignore errors here, if the cron string were invalid then the config
        // object would have already thrown an error
        cronStart = try! CronJob(pattern: config.convertCronStart) {}
        cronEnd = try! CronJob(pattern: config.convertCronEnd) {}
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        if stats != nil {
            statistics = stats!
        } else {
            statistics = Statistic()
        }
        log = config.log
        videoConversionConfig = VideoConversionConfig(container: config.convertVideoContainer, videoCodec: config.convertVideoCodec, audioCodec: config.convertAudioCodec, subtitleScan: config.convertVideoSubtitleScan, mainLanguage: config.convertLanguage, maxFramerate: config.convertVideoMaxFramerate, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        audioConversionConfig = AudioConversionConfig(container: config.convertAudioContainer, codec: config.convertAudioCodec, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)

        // I hate doing this assignment twice, but the first one complains
        // about using self in an enclosure before self is fully initialized
        cronStart = try! CronJob(pattern: config.convertCronStart) {
            self.start()
        }
        log.info("Set up conversion cron job! It will begin at \(cronStart.pattern.next(Date()))")
    }

    /// Adds a new Media object to the list of media items to convert
    func push(_ job: BaseConvertibleMedia) {
        if !jobs.contains(job) {
            jobs.append(job)
        }
    }

    @discardableResult
    fileprivate func pop() -> BaseConvertibleMedia? {
        self.activeJobs.append(self.jobs.removeFirst())
        return self.activeJobs.last
    }

    fileprivate func finish(_ job: BaseConvertibleMedia) throws {
        guard let index = self.activeJobs.index(of: job) else {
            throw ConversionError.noJobIndex
        }
        self.activeJobs.remove(at: index)
    }

    fileprivate func requeue(_ job: BaseConvertibleMedia) {
        let index = self.activeJobs.index(of: job)!
        self.jobs.append(self.activeJobs.remove(at: index))
    }

    func startNextConversion(with group: inout AsyncGroup) throws {
        guard self.active < self.maxThreads else {
            throw ConversionError.maxThreadsReached
        }
        guard var next = self.pop() else {
            throw ConversionError.noJobsLeft
        }
        group.utility {
            self.statistics.measure(.convert) {
                do {
                    if next is Video {
                        next = try (next as! Video).convert(self.videoConversionConfig, self.log)
                    } else if next is Audio {
                        next = try (next as! Audio).convert(self.audioConversionConfig, self.log)
                    } else {
                        // We shouldn't be able to convert anything else, and we
                        // shouldn't have even put anything else in the queue.
                        // Calling convert on a BaseMedia object should throw an
                        // Unimplemented Error
                        next = try next.convert(nil, self.log)
                    }
                    try self.finish(next)
                } catch MediaError.notImplemented {
                    self.log.warning("Media that is neither Video nor Audio somehow ended up in the conversion queue! => \(next.path)")
                } catch ConversionError.noJobIndex {
                    self.log.error("Error finding job index in the active jobs array. Unable to remove job, this will prevent other jobs from starting!")
                } catch {
                    self.log.warning("Error while converting media: \(next.path)")
                    self.log.error(error)
                    self.requeue(next)
                }
            }
        }
    }

    func start() {
        var now = Date()
        let end = self.cronEnd.pattern.next(now)?.date
        var convertGroup = AsyncGroup()
        while now.date! < end! {
            do {
                try self.startNextConversion(with: &convertGroup)
            } catch ConversionError.maxThreadsReached {
                self.log.info("Reached the concurrent conversion thread limit. Waiting for a thread to be freed")
            } catch ConversionError.noJobsLeft {
                self.log.info("All conversion jobs are either finished or currently running")
                break
            } catch {
                self.log.error("Uncaught expection occurred while converting media => '\(error)'")
            }
            while active == maxThreads {
                convertGroup.wait(seconds: 60)
            }
            now = Date()
        }
    }

    convenience init(_ path: Path) throws {
        try self.init(path.read())
    }

    convenience init(_ str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    required init(json: JSON) throws {
        let configFile = Path(try json.get("configPath"))
        let configString: String = try configFile.read()
        config = try Config(configString)
        configPath = config.configFile
        // Ignore errors here, if the cron string were invalid then the config
        // object would have already thrown an error
        cronStart = try! CronJob(pattern: config.convertCronStart) {}
        cronEnd = try! CronJob(pattern: config.convertCronEnd) {}
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        statistics = Statistic()
        log = config.log
        videoConversionConfig = VideoConversionConfig(container: config.convertVideoContainer, videoCodec: config.convertVideoCodec, audioCodec: config.convertAudioCodec, subtitleScan: config.convertVideoSubtitleScan, mainLanguage: config.convertLanguage, maxFramerate: config.convertVideoMaxFramerate, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        audioConversionConfig = AudioConversionConfig(container: config.convertAudioContainer, codec: config.convertAudioCodec, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        jobs = ConversionQueue.setupJobs(try json.get("jobs"))

        // I hate doing this assignment twice, but the first one complains
        // about using self in an enclosure before self is fully initialized
        cronStart = try! CronJob(pattern: config.convertCronStart) {
            self.start()
        }
        log.info("Set up conversion cron job! It will begin at \(cronStart.pattern.next(Date()))")
    }

    private static func setupJobs(_ jobs: [BaseConvertibleMedia]) -> [BaseConvertibleMedia] {
        var conversions: [BaseConvertibleMedia] = []
        for job in jobs {
            if job is Video {
                conversions.append((job as! Video))
            } else if job is Audio {
                conversions.append((job as! Audio))
            }
        }
        return conversions
    }

    public func encoded() -> JSON {
        return [
            "configPath": configPath.string,
            "jobs": jobs.encoded()
        ]
    }

    private func serialized() throws -> String {
        return try self.encoded().serialized()
    }

    public func save(to: Path) throws {
        var file: Path
        if to.isDirectory {
            file = to
        } else {
            file = to.parent
        }
        file += ConversionQueue.filename
        try file.write(self.serialized(), force: true)
    }
}

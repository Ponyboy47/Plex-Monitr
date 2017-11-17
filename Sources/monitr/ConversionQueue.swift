import PathKit
import Async
import SwiftyBeaver
import Cron

enum ConversionError: Error {
    case maxThreadsReached
    case noJobsLeft
    case noJobIndex
}

class ConversionQueue: JSONConvertible {
    static let filename: String = "conversionqueue.json"

    fileprivate var configPath: Path
    fileprivate var statistics: Statistic
    fileprivate var maxThreads: Int
    fileprivate var deleteOriginal: Bool
    fileprivate var log: SwiftyBeaver.Type
    fileprivate var videoConversionConfig: VideoConversionConfig
    fileprivate var audioConversionConfig: AudioConversionConfig

    fileprivate var jobs: [ConvertibleMedia] {
        return (videoJobs as [ConvertibleMedia]) + (audioJobs as [ConvertibleMedia])
    }
    fileprivate var videoJobs: [Video] = []
    fileprivate var audioJobs: [Audio] = []
    fileprivate var activeJobs: [ConvertibleMedia] = []

    var conversionGroup: AsyncGroup = AsyncGroup()
    var stop: Bool = false

    var active: Int {
        return activeJobs.count
    }
    var waiting: Int {
        return jobs.count
    }

    init(_ config: Config, statistics stats: Statistic? = nil) {
        configPath = config.configFile
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
    }

    /// Adds a new Media object to the list of media items to convert
    func push(_ job: inout ConvertibleMedia) {
        if !jobs.contains(where: { e in
            return e.path == job.path
                    || e.plexFilename == job.plexFilename
                    && e.finalDirectory == job.finalDirectory
        }) {
            if job is Video {
                videoJobs.append(job as! Video)
            } else if job is Audio {
                audioJobs.append(job as! Audio)
            } else {
                self.log.warning("Job is neither Audio nor Video and will not be added to the array of jobs.")
            }
        }
    }

    @discardableResult
    fileprivate func pop() -> ConvertibleMedia? {
        guard let job = self.jobs.first else { return nil }
        if job is Video {
            self.activeJobs.append(self.videoJobs.removeFirst())
        } else if job is Audio {
            self.activeJobs.append(self.audioJobs.removeFirst())
        } else {
            self.log.warning("First job is of an unknown type!")
            return nil
        }
        return self.activeJobs.last
    }

    fileprivate func finish(_ job: ConvertibleMedia) throws {
        guard let index = self.activeJobs.index(where: {  e in
            return e.path == job.path
                || e.plexFilename == job.plexFilename
                && e.finalDirectory == job.finalDirectory
        }) else {
            throw ConversionError.noJobIndex
        }
        self.activeJobs.remove(at: index)
    }

    fileprivate func requeue(_ job: ConvertibleMedia) {
        // This should be safe to force unwrap because active jobs will only
        // ever get items from the jobs arrays
        let index = self.activeJobs.index(where: { e in
            return e.path == job.path
                || e.plexFilename == job.plexFilename
                && e.finalDirectory == job.finalDirectory
        })!

        if job is Video {
            self.videoJobs.append(self.activeJobs.remove(at: index) as! Video)
        } else if job is Audio {
            self.audioJobs.append(self.activeJobs.remove(at: index) as! Audio)
        } else {
            self.log.warning("Job is of an unknow type and cannot be re-queued")
        }
    }

    func startNextConversion() throws {
        guard self.active < self.maxThreads else {
            throw ConversionError.maxThreadsReached
        }
        guard var next = self.pop() else {
            throw ConversionError.noJobsLeft
        }
        conversionGroup.utility {
            self.statistics.measure(.convert) {
                do {
                    var config: ConversionConfig?
                    if next is Video {
                        config = self.videoConversionConfig
                    } else if next is Audio {
                        config = self.audioConversionConfig
                    }
                    next = try next.convert(config, self.log)
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
        self.log.info("Beginning conversion cron job")
        while !stop {
            do {
                try self.startNextConversion()
            } catch ConversionError.maxThreadsReached {
                self.log.info("Reached the concurrent conversion thread limit. Waiting for a thread to be freed")
            } catch ConversionError.noJobsLeft {
                self.log.info("All conversion jobs are either finished or currently running")
                break
            } catch {
                self.log.error("Uncaught expection occurred while converting media => '\(error)'")
            }
            while active == maxThreads && !stop {
                conversionGroup.wait(seconds: 60)
            }
        }
        self.log.info("Conversion cron job will stop as soon as the current conversion jobs have finished")
        conversionGroup.wait()
        self.log.info("The conversion cron job is officially done running (for now)")
    }

    convenience init(_ path: Path) throws {
        try self.init(path.read())
    }

    convenience init(_ str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    required init(json: JSON) throws {
        configPath = Path(try json.get("configPath"))
        config = try Config(configPath.read())
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        statistics = Statistic()
        log = config.log
        videoConversionConfig = VideoConversionConfig(container: config.convertVideoContainer, videoCodec: config.convertVideoCodec, audioCodec: config.convertAudioCodec, subtitleScan: config.convertVideoSubtitleScan, mainLanguage: config.convertLanguage, maxFramerate: config.convertVideoMaxFramerate, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        audioConversionConfig = AudioConversionConfig(container: config.convertAudioContainer, codec: config.convertAudioCodec, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        videoJobs = try json.get("videoJobs")
        audioJobs = try json.get("audioJobs")
    }

    public func encoded() -> JSON {
        return [
            "configPath": configPath.string,
            "videoJobs": videoJobs.encoded(),
            "audioJobs": audioJobs.encoded()
        ]
    }

    private func serialized() throws -> String {
        return try self.encoded().serialized()
    }

    public func save() throws {
        let file: Path = configPath.parent + ConversionQueue.filename
        try file.write(self.serialized(), force: true)
    }
}

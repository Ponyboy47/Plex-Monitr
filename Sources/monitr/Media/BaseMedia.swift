/*

 Media.swift

 Created By: Jacob Williams
 Description: This file contains the Base media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

class BaseMedia: Media {
    var path: Path
    var downpour: Downpour
    var plexName: String {
        return downpour.title.wordCased
    }
    var plexFilename: String {
        // Return the plexified name + it's extension
        return plexName + "." + (path.extension ?? "")
    }
    var finalDirectory: Path {
        return ""
    }

    required init(_ path: Path) throws {
        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path.absolute)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        // Set the media file's path to the absolute path
        path = Path(try json.get("path")).absolute
        // Create the downpour object
        downpour = Downpour(fullPath: path)
    }

    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        // If it's already in the final directory then go ahead and return
        guard !path.string.contains(finalDirectory.string) else { return }
        log.verbose("Preparing to move file: \(path.string)")
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            log.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        log.verbose("Moving media file '\(path.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        log.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        path = finalRestingPlace
    }

    class func isSupported(ext: String) -> Bool {
        print("isSupported(ext: String) is not implemented!")
        return false
    }

    /// JSONRepresentable protocol requirement
    func encoded() -> JSON {
        return [
            "path": path.string
        ]
    }

    internal struct Output {
        var stdout: String?
        var stderr: String?
        init (_ out: String?, _ err: String?) {
            stdout = out
            stderr = err
        }
    }

    internal class func execute(_ comArgs: String...) -> (Int32, Output) {
        guard let command = comArgs.first else {
            return (-1, Output(nil, "Empty command/arguments string"))
        }
        var args: [String] = []
        if comArgs.count > 1 {
            args = Array(comArgs[1..<comArgs.count])
        }
        return execute(command, args)
    }

    internal class func execute(_ command: String, _ arguments: [String]) -> (Int32, Output) {
        let task = Process()
        if !command.ends(with: "which") {
            let (whichRC, whichOutput) = execute("which", [command])
            if whichRC == 0, let whichStdout = whichOutput.stdout, !whichStdout.isEmpty {
                var processPaths = whichStdout.components(separatedBy: CharacterSet.newlines)
                task.launchPath = processPaths.reduce(processPaths[0]) { whichPathPrev, whichPathNext in
                    func checkBinLevel(_ path: String) -> Int {
                        let bin: String = "/bin"
                        let usr: String = "/usr/bin"
                        let local: String = "/usr/local/bin"
                        if path.starts(with: local) {
                            return 1
                        } else if path.starts(with: usr) {
                            return 2
                        } else if path.starts(with: bin) {
                            return 3
                        }
                        return 0
                    }
                    let prevPath: Path = Path(whichPathPrev)
                    let nextPath: Path = Path(whichPathNext)
                    if let environ = task.environment, let paths = environ["PATH"]?.components(separatedBy: ":") {
                        if paths.contains(prevPath.parent.string) && !paths.contains(nextPath.parent.string) {
                            return whichPathPrev
                        } else if !paths.contains(prevPath.parent.string) && paths.contains(nextPath.parent.string) {
                            return whichPathNext
                        } else {
                            let prevLevel = checkBinLevel(prevPath.string)
                            let nextLevel = checkBinLevel(nextPath.string)
                            if prevLevel > nextLevel {
                                return whichPathPrev
                            } else if prevLevel < nextLevel {
                                return whichPathNext
                            }
                        }
                    } else {
                        let prevLevel = checkBinLevel(prevPath.string)
                        let nextLevel = checkBinLevel(nextPath.string)
                        if prevLevel > nextLevel {
                            return whichPathPrev
                        } else if prevLevel < nextLevel {
                            return whichPathNext
                        }
                    }
                    return "/usr/bin/env"
                }
            } else {
                task.launchPath = "/usr/bin/env"
            }
        } else {
            task.launchPath = "/usr/bin/env"
        }
        task.arguments = [command] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        task.launch()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)
        let stderr = String(data: stderrData, encoding: .utf8)
        task.waitUntilExit()
        return (task.terminationStatus, Output(stdout, stderr))
    }
}

class BaseConvertibleMedia: BaseMedia, ConvertibleMedia {
    var unconvertedFile: Path?

    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws {
        throw MediaError.notImplemented
    }

    override func move(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        try super.move(to: plexPath, log: log)
        if let _ = unconvertedFile {
            try moveUnconverted(to: plexPath, log: log)
        }
    }

    func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        guard let unconvertedPath = unconvertedFile else { return }
        // If it's already in the final directory then go ahead and return
        guard !unconvertedPath.string.contains(finalDirectory.string) else { return }

        log.verbose("Preparing to move file: \(unconvertedPath.string)")
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            log.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + "\(plexName) - original.\(unconvertedPath.extension ?? "")"

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        log.verbose("Moving media file '\(unconvertedPath.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try unconvertedPath.move(finalRestingPlace)
        log.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        unconvertedFile = finalRestingPlace
    }

    class func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        throw MediaError.notImplemented
    }
}

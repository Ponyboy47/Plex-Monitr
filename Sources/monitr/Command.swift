//
//  Execute.swift
//  Strings
//
//  Created by Jacob Williams on 6/25/17.
//

import Foundation
import PathKit

public struct Command {
    public struct Output {
        var stdout: String?
        var stderr: String?
        init (_ out: String?, _ err: String?) {
            stdout = out
            stderr = err
        }
    }

    public static func execute(_ comArgs: String...) -> (Int32, Output) {
        guard let command = comArgs.first else {
            return (-1, Output(nil, "Empty command/arguments string"))
        }
        var args: [String] = []
        if comArgs.count > 1 {
            args = Array(comArgs[1..<comArgs.count])
        }
        return execute(command, args)
    }

    public static func execute(_ command: String, _ arguments: [String]) -> (Int32, Output) {
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

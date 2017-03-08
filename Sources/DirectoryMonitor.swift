/*

    DirectoryMonitor.swift

    Created By: Jacob Williams
    Description: This file contains the class that monitors a directory for
                   write events and notifies a delegate when a new write occurs. This was
                   originally taken from an Apple website, but I updated it to work with the
                   latest swift...and to semi-work on Linux. (Currently
                   DispatchSourceFileSystemObject is not available on Linux).
    License: MIT License

*/

import Foundation
#if os(Linux)
import Dispatch
#endif

/// A protocol that allows delegates of `DirectoryMonitor` to respond to changes in a directory.
protocol DirectoryMonitorDelegate: class {
    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor)
}

class DirectoryMonitor {
    // MARK: Properties

    /// The `DirectoryMonitor`'s delegate who is responsible for responding to `DirectoryMonitor` updates.
    weak var delegate: DirectoryMonitorDelegate?

    /// A dispatch queue used for sending file changes in the directory.
    let directoryMonitorQueue = DispatchQueue(label: "com.monitr.directorymonitor", attributes: [.concurrent])

    #if os(Linux)
    /// A dispatch source that submits the event handler block based on a timer.
    var directoryMonitorSource: DispatchSourceTimer?

    /// The interval to run at
    var interval: Int

    /// The leeway with the running interval
    var leeway: Int

    // MARK: Initializers
    init(interval: Int = 60, leeway: Int = 10) {
        self.interval = interval
        self.leeway = leeway
    }
    #else
    /// A dispatch source to monitor a file descriptor created from the directory.
    var directoryMonitorSource: DispatchSourceFileSystemObject?

    /// A file descriptor for the monitored directory.
    var monitoredDirectoryFileDescriptor: Int32 = -1

    /// URL for the directory being monitored.
    var URL: URL

    // MARK: Initializers
    init(URL: URL) {
        self.URL = URL
    }
    #endif

    // MARK: Monitoring

    func startMonitoring() {
        #if os(Linux)
        if directoryMonitorSource == nil {
            directoryMonitorSource = DispatchSource.makeTimerSource(queue: directoryMonitorQueue)
            directoryMonitorSource?.scheduleRepeating(deadline: .now() + .seconds(interval), interval: .seconds(interval), leeway: .seconds(leeway))
            directoryMonitorSource?.setEventHandler {
                print("Time event occured")
                self.delegate?.directoryMonitorDidObserveChange(self)
                return
            }

            directoryMonitorSource?.setCancelHandler {
                print("Stopping timer")
                self.directoryMonitorSource = nil
            }
        }
        #else
        // Listen for changes to the directory (if we are not already).
        if directoryMonitorSource == nil && monitoredDirectoryFileDescriptor == -1 {
            // Open the directory referenced by URL for monitoring only.
            monitoredDirectoryFileDescriptor = open(URL.path, O_EVTONLY)

            // Define a dispatch source monitoring the directory for additions, deletions, and renamings.
            directoryMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: monitoredDirectoryFileDescriptor, eventMask: .write, queue: directoryMonitorQueue)

            // Define the block to call when a file change is detected.
            directoryMonitorSource?.setEventHandler {
                // Call out to the `DirectoryMonitorDelegate` so that it can react appropriately to the change.
                self.delegate?.directoryMonitorDidObserveChange(self)
                return
            }

            // Define a cancel handler to ensure the directory is closed when the source is cancelled.
            directoryMonitorSource?.setCancelHandler {
                close(self.monitoredDirectoryFileDescriptor)
                self.monitoredDirectoryFileDescriptor = -1
                self.directoryMonitorSource = nil
            }
        }
        #endif

        // Start monitoring the directory via the source.
        directoryMonitorSource?.resume()
    }

    /// Stop monitoring the directory via the source.
    func stopMonitoring() {
        directoryMonitorSource?.cancel()
    }
}

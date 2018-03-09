/*

    DirectoryMonitor.swift

    Created By: Jacob Williams
    Description: This file contains the class that monitors a directory for
                   write events and notifies a delegate when a new write occurs. This was
                   originally taken from an Apple website, but I updated it to work with the
                   latest swift...and am using the Inotify module to make this work with linux
                   as well.
                   Here is the link to the original file:
                       https://developer.apple.com/library/content/samplecode/Lister/Listings/ListerKit_DirectoryMonitor_swift.html
    License: Apple License (See DirectoryMonitor_LICENSE.txt)

*/

// swiftlint:disable identifier_name

import Foundation
#if os(Linux)
import Dispatch
import Inotify
public let O_EVTONLY = O_RDONLY
#endif

/// A protocol that allows delegates of `DirectoryMonitor` to respond to changes in a directory.
protocol DirectoryMonitorDelegate: class {
    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor)
}

enum DirectoryMonitorError: Error {
    case noInotify
}

final class DirectoryMonitor {
    // MARK: Properties

    /// The `DirectoryMonitor`'s delegate who is responsible for responding to `DirectoryMonitor` updates.
    weak var delegate: DirectoryMonitorDelegate?

    /// A dispatch queue used for sending file changes in the directory.
    let directoryMonitorQueue = DispatchQueue(label: "com.monitr.directorymonitor", attributes: [.concurrent])

    #if os(Linux)
    var inotify: Inotify?
    #else
    /// A dispatch source to monitor a file descriptor created from the directory.
    var directoryMonitorSource: DispatchSourceFileSystemObject?
    #endif

    /// A file descriptor for the monitored directory.
    var monitoredDirectoryFileDescriptor: Int32 = -1

    /// URL for the directory being monitored.
    var URL: URL

    // MARK: Initializers
    init(URL: URL) {
        self.URL = URL
        #if os(Linux)
        do {
            self.inotify = try Inotify(eventWatcher: SelectEventWatcher.self, qos: .background, watching: self.URL.path.replacingOccurrences(of: "file://", with: ""), for: .movedTo) { _ in
                self.delegate?.directoryMonitorDidObserveChange(self)
            }
        } catch {
            fatalError("Error creating inotify: \(error)")
        }
        #endif
    }

    // MARK: Monitoring

    func startMonitoring() throws {
        // Listen for changes to the directory (if we are not already).
        #if os(Linux)
        guard let i = self.inotify else {
            throw DirectoryMonitorError.noInotify
        }
        i.start()
        #else
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

        // Start monitoring the directory via the source.
        directoryMonitorSource?.resume()
        #endif
    }

    /// Stop monitoring the directory via the source.
    func stopMonitoring() {
        #if os(Linux)
        inotify?.stop()
        #else
        directoryMonitorSource?.cancel()
        #endif
    }
}

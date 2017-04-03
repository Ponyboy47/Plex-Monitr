/*

    DirectoryMonitor.swift

    Created By: Jacob Williams
    Description: This file contains the class that monitors a directory for
                   write events and notifies a delegate when a new write occurs. This was
                   originally taken from an Apple website, but I updated it to work with the
                   latest swift...and to semi-work on Linux. (Currently
                   DispatchSourceFileSystemObject is not available on Linux).
                   Here is the link to the original file:
                       https://developer.apple.com/library/content/samplecode/Lister/Listings/ListerKit_DirectoryMonitor_swift.html
    License: Apple License (See DirectoryMonitor_LICENSE.txt)

*/

import Foundation
#if os(Linux)
import Dispatch
import Glibc
import inotify
import CSelect
public let O_EVTONLY = O_RDONLY
#endif

/// A protocol that allows delegates of `DirectoryMonitor` to respond to changes in a directory.
protocol DirectoryMonitorDelegate: class {
    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor)
}

enum DirectoryMonitorError: Error {
    enum invalidFileDescriptor: Error {
        case inotify
        case directory
    }
}

final class DirectoryMonitor {
    // MARK: Properties

    /// The `DirectoryMonitor`'s delegate who is responsible for responding to `DirectoryMonitor` updates.
    weak var delegate: DirectoryMonitorDelegate?

    /// A dispatch queue used for sending file changes in the directory.
    let directoryMonitorQueue = DispatchQueue(label: "com.monitr.directorymonitor", attributes: [.concurrent])

    #if os(Linux)
    var inotifyFileDescriptor: Int32 = -1
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
    }

    // MARK: Monitoring

    func startMonitoring() throws {
        // Listen for changes to the directory (if we are not already).
        #if os(Linux)
        inotifyFileDescriptor = inotify_init()
        guard inotifyFileDescriptor > 0 else {
            throw DirectoryMonitorError.invalidFileDescriptor.inotify
        }
        monitoredDirectoryFileDescriptor = inotify_add_watch(inotifyFileDescriptor, URL.path, UInt32(IN_MOVED_TO))
        directoryMonitorQueue.async {
            while true {
                // Get the set of file descriptors
                var fileDescriptorSet: fd_set = fd_set()
                fd_zero(&fileDescriptorSet)
                fd_setter(self.inotifyFileDescriptor, &fileDescriptorSet)

                // We wait here until an inotify event is triggered
                let fileDescriptor = select(FD_SETSIZE, &fileDescriptorSet, nil, nil, nil)
                if fileDescriptor > 0 {
                    let bufferSize = 1024
                    let buffer = UnsafeMutableRawPointer(malloc(bufferSize))
                    // If we don't read inotify's buffer, then it doesn't get
                    // cleared and this triggers the delegate method infinitely
                    let _ = read(self.inotifyFileDescriptor, buffer!, bufferSize)
                    // Trigger the even on the delegate
                    self.delegate?.directoryMonitorDidObserveChange(self)
                    // Free the buffer when we're done to prevent memory leaks
                    free(buffer)
                }
            }
        }
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
        close(inotifyFileDescriptor)
        // Set this to -1 to prevent reusing an old file descriptor
        inotifyFileDescriptor = -1
        #else
        directoryMonitorSource?.cancel()
        #endif
    }
}

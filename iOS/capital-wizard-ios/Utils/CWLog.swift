//
//  CWLog.swift
//  capital-wizard-ios
//
//  In-memory ring buffer of the app's stdout/stderr output, surfaced to the
//  web app's bug reporter via the native bridge (`request-logs`). It tees the
//  standard streams through pipes so it captures print()/NSLog() output while
//  still forwarding everything to the original descriptors (Xcode console keeps
//  working). Bounded to the most recent lines so memory stays flat.
//

import Foundation

final class CWLog {
    static let shared = CWLog()

    private let maxLines = 500
    private let queue = DispatchQueue(label: "com.capitalwizard.cwlog")

    private var lines: [String] = []
    private var started = false

    // Retained for the process lifetime once capture starts.
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var stdoutRemainder = ""
    private var stderrRemainder = ""

    private init() {}

    /// Begin teeing stdout/stderr into the ring buffer. Call once, early in app
    /// launch. No-op if already started.
    func start() {
        let shouldStart: Bool = queue.sync {
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        stdoutPipe = makePipe(replacing: STDOUT_FILENO, tee: originalStdout, isStderr: false)
        stderrPipe = makePipe(replacing: STDERR_FILENO, tee: originalStderr, isStderr: true)

        // Redirecting stdout to a pipe makes it *fully* buffered, so a sparse
        // print() can sit unforwarded indefinitely. Force line buffering so each
        // line reaches the tee (and this ring buffer) promptly.
        setlinebuf(stdout)
        setlinebuf(stderr)

        log("CWLog capture started", category: "App")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Append an explicit, timestamped line to the buffer and echo it to the real
    /// console. Use this for structured app logging (lifecycle, errors) so the bug
    /// report has detail regardless of stdout buffering or os_log routing — i.e.
    /// without depending on the fragile stdout/stderr tee.
    func log(_ message: String, category: String = "App") {
        queue.async {
            let line = "\(Self.timeFormatter.string(from: Date())) [\(category)] \(message)"
            self.appendLocked(line)
            // Echo to the real console, bypassing the stdout tee so it is not
            // ingested a second time. Falls back to STDOUT before capture starts.
            let fd = self.originalStdout >= 0 ? self.originalStdout : STDOUT_FILENO
            if let data = (line + "\n").data(using: .utf8) {
                data.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, data.count) }
            }
        }
    }

    private func makePipe(replacing fd: Int32, tee: Int32, isStderr: Bool) -> Pipe {
        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Forward to the real console so Xcode logging is unaffected.
            if tee >= 0 {
                data.withUnsafeBytes { raw in
                    _ = write(tee, raw.baseAddress, data.count)
                }
            }
            self?.ingest(String(decoding: data, as: UTF8.self), isStderr: isStderr)
        }
        return pipe
    }

    private func ingest(_ text: String, isStderr: Bool) {
        queue.async {
            let combined = (isStderr ? self.stderrRemainder : self.stdoutRemainder) + text
            var parts = combined.components(separatedBy: "\n")
            // The trailing element is the still-incomplete line; hold it for next time.
            let remainder = parts.removeLast()
            if isStderr { self.stderrRemainder = remainder } else { self.stdoutRemainder = remainder }
            for line in parts where !line.isEmpty {
                self.appendLocked(line)
            }
        }
    }

    /// Append an explicit line directly to the buffer.
    func append(_ line: String) {
        queue.async { self.appendLocked(line) }
    }

    private func appendLocked(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Snapshot of the most recent buffered lines (oldest → newest).
    func snapshot(limit: Int = 500) -> [String] {
        queue.sync {
            lines.count <= limit ? lines : Array(lines.suffix(limit))
        }
    }
}

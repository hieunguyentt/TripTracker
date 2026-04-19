//
//  LogManager.swift
//  TripTracker
//
//  Captures all stdout/stderr (including print()) to date-based log files.
//  Files are stored in Library/Caches/Logs/ and are NEVER deleted.
//
//  Usage:
//    LogManager.shared.start()   — call once in AppDelegate
//    LogManager.shared.log("…")  — optional explicit logging
//
//  Log file naming: yyyy-MM-dd.log (one file per day)
//  New output is appended so relaunching the app continues the same day's file.
//

import Foundation
import UIKit

public class LogManager: NSObject {

    static let shared = LogManager()

    /// Default recipient for log emails.
    static let defaultEmail = "hieu.nguyen@sw.innova.com"

    /// Directory where log files are stored (Caches/Logs/).
    private(set) var logsDirectory: URL?

    /// File handle for today's log file.
    private var fileHandle: FileHandle?

    /// Date string of the currently open log file.
    private var currentDateString: String = ""

    /// Original stdout descriptor (saved so we can tee output).
    private var originalStdout: Int32 = -1

    /// Pipe that captures stdout.
    private var stdoutPipe: Pipe?

    /// Timer for daily auto-send at 23:59.
    private var dailySendTimer: Timer?

    /// Tracks the last date we auto-sent logs (prevents duplicate sends).
    private var lastAutoSendDate: String = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private override init() {
        super.init()
        setupLogsDirectory()
        loadLastAutoSendDate()
    }

    // MARK: - Setup

    private func setupLogsDirectory() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("❌ LogManager: Cannot access Caches directory")
            return
        }
        let logsDir = caches.appendingPathComponent("Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            logsDirectory = logsDir
        } catch {
            print("❌ LogManager: Failed to create Logs directory: \(error)")
        }
    }

    // MARK: - Public API

    /// Start capturing all stdout output to today's log file.
    /// Call once in AppDelegate didFinishLaunching.
    public func start() {
        openTodayLogFile()
        redirectStdout()
        scheduleDailyAutoSend()

        // Write a session header
        let header = "\n"
            + "════════════════════════════════════════════════════════════════\n"
            + "  TripTracker Session Started: \(timestampFormatter.string(from: Date()))\n"
            + "════════════════════════════════════════════════════════════════\n\n"
        writeToFile(header)

        // Check if we missed today's auto-send (app was killed and relaunched after 23:59)
        checkMissedAutoSend()
    }

    /// Explicitly log a message (also goes to stdout → file).
    public func log(_ message: String) {
        print("📝 \(message)")
    }

    // MARK: - Daily Auto-Send at 23:59

    /// Schedule a repeating timer that checks every 30 seconds if it's time to send.
    private func scheduleDailyAutoSend() {
        dailySendTimer?.invalidate()
        // Check every 30 seconds — lightweight and catches 23:59 reliably.
        dailySendTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkAndAutoSend()
        }
        if let timer = dailySendTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        print("📧 Daily auto-send scheduled (checks every 30s for 23:59)")
    }

    /// Check if current time is 23:59 and we haven't sent today yet.
    private func checkAndAutoSend() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let todayStr = dateFormatter.string(from: now)

        // Trigger at 23:59
        guard hour == 23 && minute == 59 else { return }

        // Already sent today?
        guard todayStr != lastAutoSendDate else { return }

        print("📧 Auto-send triggered at 23:59 — sending today's log")
        lastAutoSendDate = todayStr
        UserDefaults.standard.set(todayStr, forKey: "tt_lastAutoSendLogDate")

        // Present email composer from the topmost view controller
        DispatchQueue.main.async {
            self.presentAutoSendEmail()
        }
    }

    /// Check if we missed today's send (e.g., app relaunched after 23:59 but before midnight).
    private func checkMissedAutoSend() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let todayStr = dateFormatter.string(from: now)

        // If it's past 23:59 and we haven't sent today, send now
        if hour == 23 && todayStr != lastAutoSendDate {
            let minute = calendar.component(.minute, from: now)
            if minute >= 59 {
                print("📧 Missed auto-send detected — sending now")
                lastAutoSendDate = todayStr
                UserDefaults.standard.set(todayStr, forKey: "tt_lastAutoSendLogDate")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.presentAutoSendEmail()
                }
            }
        }
    }

    private func loadLastAutoSendDate() {
        lastAutoSendDate = UserDefaults.standard.string(forKey: "tt_lastAutoSendLogDate") ?? ""
    }

    private func presentAutoSendEmail() {
        guard let topVC = Self.topViewController() else {
            print("📧 Cannot auto-send — no visible view controller")
            return
        }
        if topVC.presentedViewController != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.presentAutoSendEmail()
            }
            return
        }
        let todayStr = dateFormatter.string(from: Date())
        let logFiles = getAllLogFiles()
        let desc = "TripTracker Daily Log — \(todayStr)\nFiles: \(logFiles.count)"
        var items: [Any] = [desc]
        items.append(contentsOf: Array(logFiles.prefix(3)))
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.setValue("TripTracker Daily Log — \(todayStr)", forKey: "subject")
        if let popover = vc.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        }
        topVC.present(vc, animated: true)
    }

    /// Find the topmost visible view controller.
    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = rootVC
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
            top = visible
        }
        return top
    }

    /// Get all log file URLs sorted newest first.
    public func getAllLogFiles() -> [URL] {
        guard let dir = logsDirectory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Get today's log file URL.
    public func getTodayLogFile() -> URL? {
        guard let dir = logsDirectory else { return nil }
        let todayStr = dateFormatter.string(from: Date())
        let url = dir.appendingPathComponent("\(todayStr).log")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Get total size of all log files (for display in Settings).
    public func totalLogSize() -> String {
        let files = getAllLogFiles()
        var total: UInt64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        if total < 1024 { return "\(total) B" }
        if total < 1024 * 1024 { return String(format: "%.1f KB", Double(total) / 1024) }
        return String(format: "%.1f MB", Double(total) / (1024 * 1024))
    }

    // MARK: - File Management

    private func openTodayLogFile() {
        guard let dir = logsDirectory else { return }
        let todayStr = dateFormatter.string(from: Date())

        // Already open for today
        if todayStr == currentDateString, fileHandle != nil { return }

        // Close previous file handle
        fileHandle?.closeFile()
        fileHandle = nil

        let filePath = dir.appendingPathComponent("\(todayStr).log")

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: filePath.path) {
            FileManager.default.createFile(atPath: filePath.path, contents: nil)
        }

        fileHandle = FileHandle(forWritingAtPath: filePath.path)
        fileHandle?.seekToEndOfFile()
        currentDateString = todayStr
    }

    private func writeToFile(_ text: String) {
        // Check if we need to roll over to a new day
        let todayStr = dateFormatter.string(from: Date())
        if todayStr != currentDateString {
            openTodayLogFile()
        }

        if let data = text.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    /// Prepend timestamp to each line before writing to file.
    /// Example: 31/03/2026 16:25:03.142 | 📍 GPS fix — acc:9m spd:12.3 m/s
    private func writeTimestampedLines(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var output = ""

        for (i, line) in lines.enumerated() {
            let isLast = (i == lines.count - 1)

            if line.isEmpty {
                // Preserve blank lines (but don't timestamp them)
                if !isLast { output += "\n" }
            } else {
                let ts = timestampFormatter.string(from: Date())
                output += "\(ts) | \(line)"
                if !isLast { output += "\n" }
            }
        }

        // If original text ended with \n, keep it
        if text.hasSuffix("\n") && !output.hasSuffix("\n") {
            output += "\n"
        }

        writeToFile(output)
    }

    // MARK: - stdout Redirection

    private func redirectStdout() {
        // Save original stdout
        originalStdout = dup(STDOUT_FILENO)

        // Create a pipe
        let pipe = Pipe()
        stdoutPipe = pipe

        // Redirect stdout to our pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        // Also redirect stderr so crash / assertion logs are captured
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Read from pipe on a background queue
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write to the original stdout (so Xcode console still works — no timestamp)
            if let self = self, self.originalStdout >= 0 {
                data.withUnsafeBytes { bytes in
                    if let ptr = bytes.baseAddress {
                        write(self.originalStdout, ptr, data.count)
                    }
                }
            }

            // Write to log file WITH timestamp on each line
            if let text = String(data: data, encoding: .utf8) {
                self?.writeTimestampedLines(text)
            }
        }
    }
}



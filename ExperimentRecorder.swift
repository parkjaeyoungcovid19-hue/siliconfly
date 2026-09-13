// ExperimentRecorder.swift — asynchronous CSV recorder for compact lab telemetry.

import Foundation

final class ExperimentRecorder {
    private let queue = DispatchQueue(label: "siliconfly.lab.recorder", qos: .utility)
    private let lock = NSLock()
    private let baseDirectory: URL?
    private var telemetryHandle: FileHandle?
    private var eventsHandle: FileHandle?
    private var _path: String?
    private var _recording = false

    var isRecording: Bool { lock.lock(); defer { lock.unlock() }; return _recording }
    var path: String? { lock.lock(); defer { lock.unlock() }; return _path }

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    @discardableResult
    func start() -> String? {
        lock.lock()
        if _recording { let p = _path; lock.unlock(); return p }
        lock.unlock()

        let fm = FileManager.default
        let base = baseDirectory ?? fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("SiliconFlyExperiments", isDirectory: true)
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stem = "experiment-\(formatter.string(from: Date()))"
            var dir = base.appendingPathComponent(stem, isDirectory: true)
            var suffix = 2
            while fm.fileExists(atPath: dir.path) {
                dir = base.appendingPathComponent("\(stem)-\(suffix)", isDirectory: true)
                suffix += 1
            }
            try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            let telemetryURL = dir.appendingPathComponent("telemetry.csv")
            let eventsURL = dir.appendingPathComponent("events.jsonl")
            let metadataURL = dir.appendingPathComponent("metadata.json")
            fm.createFile(atPath: telemetryURL.path, contents: Data(LabTelemetry.csvHeader.utf8))
            fm.createFile(atPath: eventsURL.path, contents: Data())
            let meta: [String: Any] = [
                "format": "SiliconFly Virtual Fly Lab V2",
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "telemetry": "telemetry.csv",
                "events": "events.jsonl"
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            try metaData.write(to: metadataURL, options: .atomic)
            let tfh = try FileHandle(forWritingTo: telemetryURL)
            let efh = try FileHandle(forWritingTo: eventsURL)
            try tfh.seekToEnd(); try efh.seekToEnd()
            lock.lock()
            telemetryHandle = tfh; eventsHandle = efh; _path = dir.path; _recording = true
            lock.unlock()
            mark(kind: "recording_started", detail: "Virtual Fly Lab V2")
            return dir.path
        } catch {
            fputs("lab recorder: \(error)\n", stderr)
            return nil
        }
    }

    func append(_ sample: LabTelemetry) {
        lock.lock()
        let active = _recording
        let fh = telemetryHandle
        lock.unlock()
        guard active, let fh else { return }
        let data = Data(sample.csvLine.utf8)
        queue.async {
            do { try fh.write(contentsOf: data) }
            catch { fputs("lab recorder write: \(error)\n", stderr) }
        }
    }

    func mark(kind: String, detail: String, commandID: Int? = nil) {
        lock.lock(); let active = _recording; let fh = eventsHandle; lock.unlock()
        guard active, let fh else { return }
        var obj: [String: Any] = [
            "wall_time": Date().timeIntervalSince1970,
            "kind": kind,
            "detail": detail
        ]
        if let commandID { obj["command_id"] = commandID }
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async {
            do { try fh.write(contentsOf: data) }
            catch { fputs("lab recorder event: \(error)\n", stderr) }
        }
    }

    func stop() {
        lock.lock()
        guard _recording else { lock.unlock(); return }
        let tfh = telemetryHandle, efh = eventsHandle
        telemetryHandle = nil; eventsHandle = nil
        _recording = false
        lock.unlock()

        let stopObj: [String: Any] = [
            "wall_time": Date().timeIntervalSince1970,
            "kind": "recording_stopped",
            "detail": "user stop"
        ]
        var stopData = (try? JSONSerialization.data(withJSONObject: stopObj, options: [.sortedKeys])) ?? Data()
        stopData.append(0x0A)
        queue.async {
            do { if !stopData.isEmpty { try efh?.write(contentsOf: stopData) } }
            catch { fputs("lab recorder event: \(error)\n", stderr) }
            do { try tfh?.close(); try efh?.close() }
            catch { fputs("lab recorder close: \(error)\n", stderr) }
        }
    }

    /// Wait until all queued writes/close operations finish. Used only by the
    /// built-in Lab self-test; normal UI recording remains fully asynchronous.
    func flushForTesting() { queue.sync {} }

    deinit { stop() }
}

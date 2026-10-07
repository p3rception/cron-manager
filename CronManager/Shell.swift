import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ShellResult {
    var status: Int32
    var out: String
    var err: String
}

/// Runs a tool synchronously on the calling thread.
/// ponytail: blocks the UI while it runs, fine for launchctl and crontab which
/// return in milliseconds; move to a Task if a slow tool is added. stdout is
/// drained before stderr, so a tool writing >64 KB to stderr would hang.
@discardableResult
func run(_ tool: String, _ args: [String], input: String? = nil) -> ShellResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    let out = Pipe(), err = Pipe(), inp = Pipe()
    process.standardOutput = out
    process.standardError = err
    if input != nil { process.standardInput = inp }
    do { try process.run() } catch {
        return ShellResult(status: -1, out: "", err: error.localizedDescription)
    }
    if let input {
        inp.fileHandleForWriting.write(Data(input.utf8))
        try? inp.fileHandleForWriting.close()
    }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ShellResult(status: process.terminationStatus,
                       out: String(decoding: o, as: UTF8.self),
                       err: String(decoding: e, as: UTF8.self))
}

/// Runs a tool and throws its stderr when it exits non-zero.
@discardableResult
func check(_ tool: String, _ args: [String], input: String? = nil) throws -> String {
    let r = run(tool, args, input: input)
    guard r.status == 0 else {
        let detail = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        throw AppError("\(([tool] + args).joined(separator: " ")) failed: \(detail.isEmpty ? "exit \(r.status)" : detail)")
    }
    return r.out
}

/// Backups live outside ~/Library/LaunchAgents because launchd would try to
/// load any plist left there, including a copy with the same Label.
let backupDir = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/CronManager")

func writeBackup(_ data: Data, name: String) throws {
    try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    try data.write(to: backupDir.appending(path: name + ".bak"), options: .atomic)
}

/// The last 32 KB of a log file.
func tail(_ path: String) -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else { return "(cannot read \(path))" }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
    let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    return text.isEmpty ? "(empty)" : text
}

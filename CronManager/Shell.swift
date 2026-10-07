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
    guard FileManager.default.fileExists(atPath: path) else { return "(no log yet, the job has not written to this file)" }
    guard let handle = FileHandle(forReadingAtPath: path) else { return "(no permission to read this file)" }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
    let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    return text.isEmpty ? "(empty)" : text
}

private func isPlain(_ c: Character) -> Bool { c.isLetter || c.isNumber || "-_./=:@%+,".contains(c) }

/// Quotes a word for /bin/sh when it has anything besides plain characters.
func shellQuote(_ word: String) -> String {
    !word.isEmpty && word.allSatisfy(isPlain) ? word : "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// A launchd argument list as one shell command line. `sh -c "..."` style
/// lists show just the inner command.
func commandLine(_ argv: [String]) -> String {
    if isShellCommand(argv) { return argv[2] }
    return argv.map(shellQuote).joined(separator: " ")
}

func isShellCommand(_ argv: [String]) -> Bool {
    argv.count == 3 && argv[1] == "-c" && ["sh", "bash", "zsh"].contains((argv[0] as NSString).lastPathComponent)
}

/// The argument list for an edited command line. An unchanged line keeps
/// `original`. A plain absolute path with plain arguments runs directly;
/// anything else runs through the original job's shell, or zsh.
func argumentList(_ command: String, original: [String]?) -> [String] {
    if let original, commandLine(original) == command { return original }
    if command.hasPrefix("/"), command.allSatisfy({ isPlain($0) || $0 == " " }) {
        return command.split(separator: " ").map(String.init)
    }
    let shell = original.flatMap { isShellCommand($0) ? $0[0] : nil } ?? "/bin/zsh"
    return [shell, "-c", command]
}

/// "Καθημερινό backup" becomes "kathemerino-backup", for labels and log names.
func slugify(_ name: String) -> String {
    let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
    return latin.lowercased().replacing(#/[^a-z0-9]+/#, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// Something that stops a job from running, with a hint on how to fix it.
struct Problem: Hashable {
    let title: String
    let hint: String
}

private let interpreters: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "python", "python3", "perl", "ruby", "node", "osascript", "php"]

/// Checks that the program, and the script an interpreter runs, exist and
/// can run. Only absolute paths are checked; PATH lookups are left alone.
func programProblems(_ argv: [String]) -> [Problem] {
    guard let program = argv.first else {
        return [Problem(title: "No program set", hint: "Edit the job and enter a command.")]
    }
    var problems = pathProblems(program, script: false)
    guard interpreters.contains((program as NSString).lastPathComponent), argv.count > 1 else { return problems }
    if isShellCommand(argv) {
        // ponytail: only the first word of a quote-free command is checked.
        if !argv[2].contains(where: { "\"'".contains($0) }), let first = argv[2].split(separator: " ").first {
            problems += pathProblems(String(first), script: false)
        }
    } else {
        problems += pathProblems(argv[1], script: true)
    }
    return problems
}

private func pathProblems(_ path: String, script: Bool) -> [Problem] {
    guard path.hasPrefix("/") else { return [] }
    if !FileManager.default.fileExists(atPath: path) {
        var hint = "\(path) does not exist. Reinstall what added this job, or delete the job."
        if let formula = path.firstMatch(of: #/^/(?:opt/homebrew|usr/local)/opt/([^/]+)//#)?.1 {
            hint = "\(path) does not exist. Reinstall it with brew install \(formula), or remove the job with brew services cleanup."
        }
        return [Problem(title: script ? "Script not found" : "Program not found", hint: hint)]
    }
    if !script, !FileManager.default.isExecutableFile(atPath: path) {
        return [Problem(title: "Program is not executable", hint: "Run chmod +x \(shellQuote(path)) in Terminal.")]
    }
    return []
}

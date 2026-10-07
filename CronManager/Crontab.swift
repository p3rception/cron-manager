import Foundation

/// One job line of the user's crontab. `id` is the line index, so it stays
/// stable across reloads as long as lines above it are unchanged.
struct CronJob: Identifiable, Equatable {
    var id: Int
    var schedule: String
    var command: String
    var enabled = true

    /// Disabled jobs are kept in the crontab as a comment with this prefix.
    static let offMarker = "#off "

    var line: String { (enabled ? "" : Self.offMarker) + schedule + " " + command }

    init(id: Int, schedule: String, command: String, enabled: Bool = true) {
        self.id = id
        self.schedule = schedule
        self.command = command
        self.enabled = enabled
    }

    /// Returns nil for comments, blank lines and environment assignments.
    /// ponytail: schedule fields are not validated, `crontab -` rejects bad
    /// ones on save.
    init?(id: Int, line: String) {
        var rest = Substring(line)
        enabled = !rest.hasPrefix(Self.offMarker)
        if !enabled { rest = rest.dropFirst(Self.offMarker.count) }
        rest = rest.drop(while: \.isWhitespace)
        guard !rest.isEmpty, !rest.hasPrefix("#") else { return nil }

        var fields: [Substring] = []
        for _ in 0..<(rest.hasPrefix("@") ? 1 : 5) {
            rest = rest.drop(while: \.isWhitespace)
            let field = rest.prefix(while: { !$0.isWhitespace })
            guard !field.isEmpty else { return nil }
            fields.append(field)
            rest = rest.dropFirst(field.count)
        }
        // The command keeps its own spacing, which can matter inside quotes.
        let command = rest.drop(while: \.isWhitespace)
        guard !command.isEmpty, !fields[0].contains("=") else { return nil }

        self.id = id
        schedule = fields.joined(separator: " ")
        self.command = String(command)
    }

    /// The schedule is one @keyword or five fields.
    var hasValidShape: Bool {
        let n = schedule.split(whereSeparator: \.isWhitespace).count
        return schedule.hasPrefix("@") ? n == 1 : n == 5
    }
}

enum Crontab {
    static let tool = "/usr/bin/crontab"

    /// Every line of the crontab, comments and environment lines included,
    /// so saving writes back everything the app does not edit.
    static func load() throws -> [String] {
        let r = run(tool, ["-l"])
        if r.status != 0 {
            if r.err.contains("no crontab") { return [] }
            throw AppError("crontab -l failed: \(r.err)")
        }
        var lines = r.out.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func save(_ lines: [String]) throws {
        try writeBackup(Data(run(tool, ["-l"]).out.utf8), name: "crontab")
        // cron ignores a last line without a newline.
        try check(tool, ["-"], input: lines.map { $0 + "\n" }.joined())
    }

    /// ponytail: runs with the app's environment, not cron's minimal one, and
    /// discards output.
    static func runNow(_ job: CronJob) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", job.command]
        try process.run()
    }
}

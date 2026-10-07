import Foundation

/// A plist in ~/Library/LaunchAgents. `plist` keeps every key so editing a
/// few of them writes the rest back unchanged.
struct Agent: Identifiable {
    let url: URL
    let plist: [String: Any]
    let broken: Bool

    var id: String { url.path }
    var label: String { plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent }

    var arguments: [String] {
        if let args = plist["ProgramArguments"] as? [String] { return args }
        return [plist["Program"] as? String].compactMap { $0 }
    }

    var logPaths: [String] {
        let paths = ["StandardOutPath", "StandardErrorPath"].compactMap { plist[$0] as? String }
        return paths.first == paths.last ? Array(paths.prefix(1)) : paths
    }

    /// StartCalendarInterval as one dictionary, or nil when absent, a list of
    /// several, or not all integers.
    var calendar: [String: Int]? {
        let value = plist["StartCalendarInterval"]
        if let dict = value as? [String: Int] { return dict }
        if let list = value as? [[String: Int]], list.count == 1 { return list[0] }
        return nil
    }

    var schedule: String {
        let parsed = Schedule(plist: plist)
        return parsed.kind == .custom ? rawSchedule : parsed.summary(login: "at login")
    }

    /// Describes schedules the editor cannot represent.
    var rawSchedule: String {
        if let n = plist["StartInterval"] as? Int { return "every \(n) s" }
        if let value = plist["StartCalendarInterval"] {
            let dicts = value as? [[String: Int]] ?? [value as? [String: Int] ?? [:]]
            return "at " + dicts.map { d in
                d.isEmpty ? "every minute" : d.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            }.joined(separator: "; ")
        }
        if plist["KeepAlive"] != nil { return "kept alive" }
        if plist["WatchPaths"] != nil || plist["QueueDirectories"] != nil { return "on file change" }
        if plist["RunAtLoad"] as? Bool == true { return "at login" }
        return "on demand"
    }

    init(url: URL) {
        self.url = url
        let parsed = (try? Data(contentsOf: url)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        plist = parsed ?? [:]
        broken = parsed == nil
    }
}

extension Agent {
    /// Problems visible from the plist and the file system.
    var fileProblems: [Problem] {
        if broken {
            return [Problem(title: "Plist cannot be read", hint: "\(url.lastPathComponent) is not a valid property list. Delete it, or fix it in a text editor.")]
        }
        if plist.isEmpty {
            return [Problem(title: "Plist is empty", hint: "It has no settings, so launchd cannot run it. Delete it unless an app writes it again.")]
        }
        var problems: [Problem] = []
        if plist["Label"] == nil {
            problems.append(Problem(title: "Label missing", hint: "launchd needs a Label key to load the job."))
        }
        problems += programProblems(arguments)
        for dir in Set(logPaths.map { ($0 as NSString).deletingLastPathComponent }).sorted()
        where !FileManager.default.fileExists(atPath: dir) {
            problems.append(Problem(title: "Log folder missing", hint: "launchd cannot start a job whose log folder does not exist. Create \(dir), or change the log path."))
        }
        if let dir = plist["WorkingDirectory"] as? String, !FileManager.default.fileExists(atPath: dir) {
            problems.append(Problem(title: "Working folder missing", hint: "\(dir) does not exist, so launchd cannot start the job."))
        }
        return problems
    }
}

/// What a `launchctl list` status means: an exit code, or minus a signal number.
func exitMeaning(_ code: Int) -> String {
    if code < 0 { return signalMeaning(-code) }
    switch code {
    case 0: return "success"
    case 1: return "general error"
    case 2: return "bad arguments"
    case 64: return "usage error"
    case 65: return "bad input data"
    case 66: return "input file missing"
    case 69: return "service unavailable"
    case 70: return "internal error"
    case 71: return "system error"
    case 73: return "cannot create output file"
    case 74: return "input/output error"
    case 75: return "temporary failure"
    case 77: return "permission denied"
    case 78: return "configuration error"
    case 126: return "not executable"
    case 127: return "command not found"
    case 129..<160: return signalMeaning(code - 128)
    default: return "error"
    }
}

private func signalMeaning(_ signal: Int) -> String {
    switch signal {
    case 2: "interrupted"
    case 6: "crashed (abort)"
    case 9: "killed"
    case 10: "crashed (bus error)"
    case 11: "crashed (segmentation fault)"
    case 15: "stopped"
    default: "killed by signal \(signal)"
    }
}

/// A job as `launchctl list` reports it. Absent from the list means not loaded.
struct AgentStatus {
    var pid: Int?
    var lastExit: Int?
}

enum Launchd {
    static let tool = "/bin/launchctl"
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents")
    static let domain = "gui/\(getuid())"

    static func agents() -> [Agent] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "plist" }
            .map(Agent.init(url:))
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Status by label, from one `launchctl list` call (PID, Status, Label columns).
    static func status() -> [String: AgentStatus] {
        var result: [String: AgentStatus] = [:]
        for line in run(tool, ["list"]).out.split(separator: "\n").dropFirst() {
            let f = line.split(separator: "\t")
            guard f.count == 3 else { continue }
            result[String(f[2])] = AgentStatus(pid: Int(f[0]), lastExit: Int(f[1]))
        }
        return result
    }

    /// Enables first so a job unloaded by this app also loads at the next login.
    static func load(_ agent: Agent) throws {
        try check(tool, ["enable", "\(domain)/\(agent.label)"])
        try check(tool, ["bootstrap", domain, agent.url.path])
    }

    /// Disables too, otherwise launchd loads the plist again at the next login.
    static func unload(_ agent: Agent) throws {
        try check(tool, ["bootout", "\(domain)/\(agent.label)"])
        try check(tool, ["disable", "\(domain)/\(agent.label)"])
    }

    /// How often launchd started the job since it was loaded. launchd keeps
    /// no last-run time, only this count.
    static func runs(_ agent: Agent) -> Int? {
        let out = run(tool, ["print", "\(domain)/\(agent.label)"]).out
        return out.firstMatch(of: #/(?m)^\truns = (\d+)$/#).flatMap { Int($0.1) }
    }

    static func kickstart(_ agent: Agent) throws {
        try check(tool, ["kickstart", "\(domain)/\(agent.label)"])
    }

    /// Writes a new or edited plist. A loaded job is reloaded so launchd picks
    /// up the change.
    static func save(_ plist: [String: Any], replacing original: Agent?, loaded: Bool) throws {
        guard let label = plist["Label"] as? String, !label.isEmpty, !label.contains("/") else {
            throw AppError("Label must be set and cannot contain \"/\".")
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = original?.url ?? dir.appending(path: "\(label).plist")
        if let original {
            try writeBackup(Data(contentsOf: original.url), name: original.url.lastPathComponent)
        } else if FileManager.default.fileExists(atPath: url.path) {
            throw AppError("\(url.path) already exists.")
        }
        if loaded, let original { try check(tool, ["bootout", "\(domain)/\(original.label)"]) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if loaded { try check(tool, ["bootstrap", domain, url.path]) }
    }

    /// Swaps the plist with its backup, so restoring twice switches back.
    static func restore(_ agent: Agent, loaded: Bool) throws {
        let name = agent.url.lastPathComponent
        let previous = try Data(contentsOf: backupURL(name))
        guard (try? PropertyListSerialization.propertyList(from: previous, format: nil)) is [String: Any] else {
            throw AppError("The saved version is not a valid plist.")
        }
        try writeBackup(Data(contentsOf: agent.url), name: name)
        if loaded { try check(tool, ["bootout", "\(domain)/\(agent.label)"]) }
        try previous.write(to: agent.url, options: .atomic)
        if loaded { try check(tool, ["bootstrap", domain, agent.url.path]) }
    }

    static func delete(_ agent: Agent, loaded: Bool) throws {
        if loaded { try check(tool, ["bootout", "\(domain)/\(agent.label)"]) }
        try FileManager.default.trashItem(at: agent.url, resultingItemURL: nil)
    }
}

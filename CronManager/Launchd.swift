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

    static func delete(_ agent: Agent, loaded: Bool) throws {
        if loaded { try check(tool, ["bootout", "\(domain)/\(agent.label)"]) }
        try FileManager.default.trashItem(at: agent.url, resultingItemURL: nil)
    }
}

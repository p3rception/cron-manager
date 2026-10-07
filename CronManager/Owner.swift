import AppKit

/// Who installed a job, worked out from the plist and the command. Checked
/// in order: AssociatedBundleIdentifiers (what Login Items uses), an .app in
/// the command, a Homebrew path, a label starting with an installed app's
/// bundle ID, then a script in the home folder.
struct Owner {
    var name: String
    /// The owning app, or the user's script, for Open and Show in Finder.
    var url: URL?
    var isApp = false
    /// SF Symbol when there is no app icon.
    var symbol = "questionmark.app.dashed"

    init(name: String, url: URL? = nil, isApp: Bool = false, symbol: String = "questionmark.app.dashed") {
        self.name = name
        self.url = url
        self.isApp = isApp
        self.symbol = symbol
    }

    init(agent: Agent) {
        let associated = agent.plist["AssociatedBundleIdentifiers"]
        for id in associated as? [String] ?? [associated as? String].compactMap({ $0 }) {
            if let app = Self.app(bundleID: id) { self = app; return }
        }
        let words = agent.arguments.joined(separator: " ")
        if let owner = Self.fromCommand(words) { self = owner; return }
        if agent.label.hasPrefix("homebrew.mxcl.") {
            self = Self.homebrew(String(agent.label.dropFirst("homebrew.mxcl.".count)))
            return
        }
        let parts = agent.label.split(separator: ".")
        for n in stride(from: parts.count, through: 2, by: -1) {
            if let app = Self.app(bundleID: parts.prefix(n).joined(separator: ".")) { self = app; return }
        }
        if agent.label.hasPrefix("com.\(NSUserName()).") {
            self.init(name: "Your script", symbol: "terminal")
            return
        }
        self.init(name: "Unknown (\(parts.prefix(2).joined(separator: ".")))")
    }

    /// For cron jobs, which only have a command.
    init(command: String) {
        self = Self.fromCommand(command) ?? Owner(name: "Unknown")
    }

    private static func fromCommand(_ command: String) -> Owner? {
        // App paths can contain spaces, so try every "/" that starts a word
        // before each ".app" until one exists on disk.
        var missing: String?
        for end in command.matches(of: #/\.app(?=/|$|\s|["'])/#) {
            let prefix = command[..<end.range.upperBound]
            for start in prefix.indices where prefix[start] == "/"
                && (start == prefix.startIndex || " \"'=".contains(prefix[prefix.index(before: start)])) {
                let path = String(prefix[start...])
                if FileManager.default.fileExists(atPath: path) {
                    let url = URL(fileURLWithPath: path)
                    return Owner(name: url.deletingPathExtension().lastPathComponent, url: url, isApp: true)
                }
                missing = path
            }
        }
        // The shortest candidate is the likeliest real path.
        if let missing {
            let app = (missing as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return Owner(name: "Missing app (\(app))", symbol: "exclamationmark.triangle")
        }
        if let match = command.firstMatch(of: #/\/(?:opt\/homebrew|usr\/local)\/(?:opt|Cellar)\/([^\/\s]+)/#) {
            return homebrew(String(match.1))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        if let match = command.firstMatch(of: #/(?:^|\s|["'])((?:~|\/Users\/[^\/\s]+)\/[^\s"']+)/#) {
            let path = (String(match.1) as NSString).expandingTildeInPath
            if path.hasPrefix(home), !path.hasPrefix(home + "Library/") {
                return Owner(name: "Your script", url: URL(fileURLWithPath: path), symbol: "terminal")
            }
        }
        return nil
    }

    private static func app(bundleID: String) -> Owner? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return Owner(name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                     url: url, isApp: true)
    }

    private static func homebrew(_ formula: String) -> Owner {
        Owner(name: "Homebrew (\(formula))", symbol: "mug")
    }
}

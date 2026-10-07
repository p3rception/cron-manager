import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var agents: [Agent] = []
    var status: [String: AgentStatus] = [:]
    var cronLines: [String] = []
    var error: String?

    var cronJobs: [CronJob] { cronLines.indices.compactMap { CronJob(id: $0, line: cronLines[$0]) } }

    init() { refresh() }

    func refresh() {
        agents = Launchd.agents()
        status = Launchd.status()
        do { cronLines = try Crontab.load() } catch { self.error = error.localizedDescription }
    }

    func isLoaded(_ agent: Agent) -> Bool { status[agent.label] != nil }

    func statusText(_ agent: Agent) -> String {
        if agent.broken { return "cannot read plist" }
        guard let s = status[agent.label] else { return "not loaded" }
        if let pid = s.pid { return "running, PID \(pid)" }
        if let exit = s.lastExit, exit != 0 { return "loaded, last exit \(exit)" }
        return "loaded"
    }

    /// Runs an action from a button, showing any error in an alert.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
        refresh()
    }

    /// Applies an edit to the crontab lines and installs the result. Refuses
    /// when the crontab changed since it was loaded, so edits made in a
    /// terminal are not overwritten.
    func writeCron(_ edit: (inout [String]) -> Void) throws {
        let current = try Crontab.load()
        guard current == cronLines else {
            cronLines = current
            throw AppError("The crontab changed outside Cron Manager. It has been reloaded, try again.")
        }
        var lines = cronLines
        edit(&lines)
        try Crontab.save(lines)
        refresh()
    }
}

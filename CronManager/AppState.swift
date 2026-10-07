import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var agents: [Agent] = []
    var status: [String: AgentStatus] = [:]
    /// By agent id. Cached because owner lookups query Launch Services.
    var owners: [String: Owner] = [:]
    /// By agent id, cached for the same reason.
    var fileProblems: [String: [Problem]] = [:]
    var cronLines: [String] = []
    var error: String?

    var cronJobs: [CronJob] { cronLines.indices.compactMap { CronJob(id: $0, line: cronLines[$0]) } }

    init() { refresh() }

    func refresh() {
        agents = Launchd.agents()
        owners = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, Owner(agent: $0)) })
        fileProblems = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.fileProblems) })
        status = Launchd.status()
        do { cronLines = try Crontab.load() } catch { self.error = error.localizedDescription }
    }

    func owner(_ agent: Agent) -> Owner { owners[agent.id] ?? Owner(agent: agent) }

    /// File problems plus a failed last run. SIGTERM (-15) is how launchd
    /// stops jobs on logout or unload, so it is not a failure.
    func problems(_ agent: Agent) -> [Problem] {
        var result = fileProblems[agent.id] ?? agent.fileProblems
        if let s = status[agent.label], s.pid == nil, let code = s.lastExit, code != 0, code != -15 {
            let hint = code == 78
                ? "launchd also reports 78 when it cannot start the program, for example when the program or a log folder is missing."
                : agent.logPaths.isEmpty ? "The job has no log. Turn on Save output in Edit to see why it fails." : "The log below may say why."
            result.append(Problem(title: "Last run failed: \(code < 0 ? "signal \(-code)" : "exit \(code)"), \(exitMeaning(code))", hint: hint))
        }
        return result
    }

    var problemCount: Int {
        agents.filter { !problems($0).isEmpty }.count + cronJobs.filter { !$0.problems.isEmpty }.count
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

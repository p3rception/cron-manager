import SwiftUI

@main
struct CronManagerApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("Cron Manager") { ContentView(state: state) }
            .defaultSize(width: 1000, height: 650)
    }
}

enum Selection: Hashable {
    case agent(String)
    case cron(Int)
}

enum Editing: Identifiable {
    case agent(Agent?)
    case cron(CronJob?)
    case copyAgent(Agent)
    case copyCron(CronJob)
    case convert(CronJob, Agent)

    var id: String {
        switch self {
        case .agent(let a): "agent:\(a?.id ?? "new")"
        case .cron(let j): "cron:\(j.map { String($0.id) } ?? "new")"
        case .copyAgent(let a): "copy:\(a.id)"
        case .copyCron(let j): "copy-cron:\(j.id)"
        case .convert(let j, _): "convert:\(j.id)"
        }
    }
}

struct ContentView: View {
    let state: AppState
    @State private var selection: Selection?
    @State private var editing: Editing?
    @State private var onlyProblems = false
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("LaunchAgents") {
                    ForEach(state.agents.filter { (!onlyProblems || !state.problems($0).isEmpty) && matches(agent: $0) }) { agent in
                        let owner = state.owner(agent)
                        row(agent.label, detail: "\(owner.name), \(state.statusText(agent)), \(agent.schedule)",
                            owner: owner, problem: state.problems(agent).first)
                            .tag(Selection.agent(agent.id))
                    }
                }
                Section("Crontab") {
                    ForEach(state.cronJobs.filter { (!onlyProblems || !$0.problems.isEmpty) && matches(search, $0.command) }) { job in
                        let owner = Owner(command: job.command)
                        row(job.baseCommand, detail: "\(owner.name), \(job.summary)\(job.enabled ? "" : ", disabled")",
                            owner: owner, problem: job.problems.first)
                            .tag(Selection.cron(job.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .searchable(text: $search, placement: .sidebar, prompt: "Label, owner or command")
            .toolbar {
                let count = state.problemCount
                Toggle(isOn: $onlyProblems) {
                    Label("\(count)", systemImage: "exclamationmark.triangle")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .help("Show only jobs that need attention")
                .accessibilityLabel("\(count) jobs need attention")
                .disabled(count == 0 && !onlyProblems)
                Menu {
                    Button("New LaunchAgent") { editing = .agent(nil) }
                    Button("New Cron Job") { editing = .cron(nil) }
                } label: { Label("New", systemImage: "plus") }
                Button { state.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        } detail: {
            switch selection {
            case .agent(let id):
                if let agent = state.agents.first(where: { $0.id == id }) {
                    AgentDetail(state: state, agent: agent, edit: { editing = .agent(agent) }, duplicate: { editing = .copyAgent(agent.copy) })
                }
            case .cron(let id):
                if let job = state.cronJobs.first(where: { $0.id == id }) {
                    CronDetail(state: state, job: job, edit: { editing = .cron(job) }, duplicate: { editing = .copyCron(job) },
                               convert: { if let agent = Agent(converting: job) { editing = .convert(job, agent) } },
                               deleted: { selection = nil })
                }
            case nil:
                Text("Select a job").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { item in
            switch item {
            case .agent(let original):
                agentEditor(original: original, template: nil)
            case .copyAgent(let template):
                agentEditor(original: nil, template: template)
            case .convert(let job, let template):
                agentEditor(original: nil, template: template) {
                    var off = job
                    off.enabled = false
                    try state.writeCron { $0[job.id] = off.line }
                }
            case .cron(let original):
                cronEditor(original: original, template: nil)
            case .copyCron(let template):
                cronEditor(original: nil, template: template)
            }
        }
        .alert("Error", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
        } message: {
            Text(state.error ?? "")
        }
    }

    /// `created` runs after a new job is saved and loaded.
    private func agentEditor(original: Agent?, template: Agent?, created: @escaping () throws -> Void = {}) -> some View {
        AgentEditor(original: original, template: template) { plist in
            try Launchd.save(plist, replacing: original, loaded: original.map(state.isLoaded) ?? false)
            state.refresh()
            // A new job is loaded right away, otherwise it would not run until the next login.
            if original == nil, let agent = state.agents.first(where: { $0.label == plist["Label"] as? String }) {
                selection = .agent(agent.id)
                state.perform {
                    try Launchd.load(agent)
                    try created()
                }
            }
        }
    }

    private func cronEditor(original: CronJob?, template: CronJob?) -> some View {
        CronEditor(original: original, template: template) { job in
            try state.writeCron { lines in
                if let original { lines[original.id] = job.line } else { lines.append(job.line) }
            }
            if original == nil { selection = .cron(state.cronLines.count - 1) }
        }
    }

    private func matches(agent: Agent) -> Bool {
        matches(search, agent.label, state.owner(agent).name, commandLine(agent.arguments))
    }

    private func matches(_ query: String, _ fields: String...) -> Bool {
        query.isEmpty || fields.contains { $0.localizedStandardContains(query) }
    }

    /// A job with a problem gets a badge on its icon, and the problem
    /// replaces the subtitle.
    private func row(_ title: String, detail: String, owner: Owner, problem: Problem?) -> some View {
        HStack {
            OwnerIcon(owner: owner, size: 22)
                .overlay(alignment: .bottomTrailing) {
                    if problem != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .offset(x: 4, y: 4)
                    }
                }
            VStack(alignment: .leading) {
                Text(title).lineLimit(1)
                Text(problem?.title ?? detail)
                    .font(.caption)
                    .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
            }
        }
    }
}

struct AgentDetail: View {
    let state: AppState
    let agent: Agent
    let edit: () -> Void
    let duplicate: () -> Void
    @State private var confirmDelete = false
    @State private var confirmRestore = false

    var body: some View {
        let loaded = state.isLoaded(agent)
        let backup = backupDate(agent.url.lastPathComponent)
        Form {
            Section {
                OwnerHeader(title: agent.label, owner: state.owner(agent))
            }
            ProblemsSection(problems: state.problems(agent))
            Section {
                LabeledContent("Status", value: state.statusText(agent))
                LabeledContent("Schedule", value: agent.schedule)
                LabeledContent("Next run", value: nextRun(loaded: loaded))
                if !agent.logPaths.isEmpty {
                    LabeledContent("Last output", value: lastOutput)
                }
                if loaded, let runs = Launchd.runs(agent) {
                    LabeledContent("Runs since loaded", value: "\(runs)")
                }
                LabeledContent("Command") { Text(commandLine(agent.arguments)).textSelection(.enabled) }
                LabeledContent("File") { Text(agent.url.path).textSelection(.enabled) }
            }
            Section {
                HStack {
                    Button(loaded ? "Unload" : "Load") {
                        state.perform { loaded ? try Launchd.unload(agent) : try Launchd.load(agent) }
                    }
                    Button("Run Now") { state.perform { try Launchd.kickstart(agent) } }.disabled(!loaded)
                    Button("Edit", action: edit).disabled(agent.broken)
                    Menu("More") {
                        Button("Duplicate...", action: duplicate).disabled(agent.broken)
                        Button("Show Plist in Finder") { NSWorkspace.shared.activateFileViewerSelecting([agent.url]) }
                        Divider()
                        Button("Restore Previous Version...") { confirmRestore = true }.disabled(backup == nil)
                    }
                    .fixedSize()
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            ForEach(agent.logPaths, id: \.self) { LogSection(path: $0) }
        }
        .formStyle(.grouped)
        .confirmationDialog("Move \(agent.label) to the Trash?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { state.perform { try Launchd.delete(agent, loaded: loaded) } }
        }
        .confirmationDialog("Restore the version from \(backup.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")?",
                            isPresented: $confirmRestore) {
            Button("Restore") { state.perform { try Launchd.restore(agent, loaded: loaded) } }
        } message: {
            Text("The current version is kept as the previous version, so you can switch back the same way.")
        }
    }

    private func nextRun(loaded: Bool) -> String {
        guard loaded else { return "not loaded" }
        let schedule = Schedule(plist: agent.plist)
        if let date = schedule.nextRun(clockAligned: false) { return describe(date) }
        switch schedule.kind {
        case .interval: return "within \(schedule.every) \(schedule.every == 1 ? String(schedule.unit.rawValue.dropLast()) : schedule.unit.rawValue), counted from the last run"
        case .atLogin: return "at next login"
        default:
            if agent.plist["KeepAlive"] != nil { return "keeps running" }
            if agent.plist["WatchPaths"] != nil || agent.plist["QueueDirectories"] != nil { return "when watched files change" }
            return "only when started"
        }
    }

    /// launchd keeps no last-run time, so the log's modified date stands in.
    private var lastOutput: String {
        let dates = agent.logPaths.compactMap {
            try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date
        }
        return dates.max().map(describe) ?? "never"
    }
}

struct LogSection: View {
    let path: String

    var body: some View {
        Section(path) {
            ScrollView {
                // Rereads the file so output from Run Now shows up live.
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Text(tail(path))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .defaultScrollAnchor(.bottom)
            .frame(minHeight: 120, maxHeight: 300)
        }
    }
}

/// "8 Oct 2026 at 18:00 (in 3 hours)"
func describe(_ date: Date) -> String {
    "\(date.formatted(date: .abbreviated, time: .shortened)) (\(date.formatted(.relative(presentation: .named))))"
}

struct ProblemsSection: View {
    let problems: [Problem]

    var body: some View {
        if !problems.isEmpty {
            Section("Needs attention") {
                ForEach(problems, id: \.self) { problem in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.title)
                            Text(problem.hint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

struct CronDetail: View {
    let state: AppState
    let job: CronJob
    let edit: () -> Void
    let duplicate: () -> Void
    let convert: () -> Void
    let deleted: () -> Void
    @State private var confirmDelete = false
    @State private var confirmRestore = false
    @State private var running = false

    var body: some View {
        Form {
            Section {
                OwnerHeader(title: job.baseCommand, owner: Owner(command: job.command))
            }
            ProblemsSection(problems: job.problems)
            Section {
                LabeledContent("Schedule", value: job.summary == job.schedule ? job.schedule : "\(job.summary) (\(job.schedule))")
                LabeledContent("Next run", value: nextRun)
                LabeledContent("Command") { Text(job.baseCommand).textSelection(.enabled) }
                LabeledContent("Status", value: job.enabled ? "enabled" : "disabled")
            }
            Section {
                HStack {
                    Button(job.enabled ? "Disable" : "Enable") {
                        var toggled = job
                        toggled.enabled.toggle()
                        state.perform { try state.writeCron { $0[job.id] = toggled.line } }
                    }
                    Button("Run Now") { running = true }
                    Button("Edit", action: edit)
                    Menu("More") {
                        Button("Duplicate...", action: duplicate)
                        Button("Convert to LaunchAgent...", action: convert)
                            .disabled(Agent(converting: job) == nil)
                            .help("launchd can't express custom cron schedules")
                        Divider()
                        Button("Restore Previous Crontab...") { confirmRestore = true }
                            .disabled(backupDate("crontab") == nil)
                    }
                    .fixedSize()
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            if let log = job.logPath { LogSection(path: log) }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $running) { RunSheet(command: job.command) }
        .confirmationDialog("Restore the crontab from \(backupDate("crontab").map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")?",
                            isPresented: $confirmRestore) {
            Button("Restore") {
                guard let lines = Crontab.backupLines() else { return }
                state.perform { try state.writeCron { $0 = lines } }
                deleted()
            }
        } message: {
            Text("It becomes:\n\n\((Crontab.backupLines() ?? []).joined(separator: "\n"))\n\nThe current crontab is kept as the previous version, so you can switch back.")
        }
        .confirmationDialog("Delete this cron job?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                state.perform { try state.writeCron { $0.remove(at: job.id) } }
                deleted()
            }
        }
    }

    private var nextRun: String {
        guard job.enabled else { return "disabled" }
        let schedule = Schedule(cron: job.schedule)
        if let date = schedule.nextRun(clockAligned: true) { return describe(date) }
        return schedule.kind == .atLogin ? "at next startup" : "not calculated for custom schedules"

    }
}

struct OwnerIcon: View {
    let owner: Owner
    let size: CGFloat

    var body: some View {
        if owner.isApp, let url = owner.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: owner.symbol)
                .font(.system(size: size * 0.7))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// The top of a detail view: the owner's icon, what owns the job and
/// buttons to open the app or find the script.
struct OwnerHeader: View {
    let title: String
    let owner: Owner

    var body: some View {
        HStack(spacing: 12) {
            OwnerIcon(owner: owner, size: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                if let url = owner.url {
                    HStack {
                        if owner.isApp {
                            Button("Open \(owner.name)") { NSWorkspace.shared.open(url) }
                        }
                        Button(owner.isApp ? "Show App in Finder" : "Show Script in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var subtitle: String {
        let name = owner.isApp ? "Added by \(owner.name)" : owner.name
        guard let url = owner.url else { return name }
        return "\(name), \((url.path as NSString).abbreviatingWithTildeInPath)"
    }
}

/// Runs a cron command and streams its output until it exits or is stopped.
struct RunSheet: View {
    let command: String
    @Environment(\.dismiss) private var dismiss
    @State private var runner = Runner()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(command).font(.headline).lineLimit(2).textSelection(.enabled)
            ScrollView {
                Text(runner.output.isEmpty ? (runner.running ? "Waiting for output..." : "(no output)") : runner.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            Text("Runs with this app's environment, which has more in PATH than cron gives the job.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if runner.running {
                    ProgressView().controlSize(.small)
                    Text("Running")
                } else if let code = runner.exitCode {
                    Text(code == 0 ? "Finished" : "Failed: \(code < 0 ? "signal \(-code)" : "exit \(code)"), \(exitMeaning(code))")
                }
                Spacer()
                if runner.running {
                    Button("Stop") { runner.stop() }
                }
                Button("Close") {
                    runner.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 640, height: 440)
        .onAppear { runner.start(command) }
    }
}

/// The process behind RunSheet. Pipe and exit callbacks arrive on
/// background threads and hop to the main actor before touching state.
@MainActor
@Observable
final class Runner {
    var output = ""
    var running = false
    /// Exit status, or minus the signal number.
    var exitCode: Int?
    private var process: Process?

    func start(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.output += text }
        }
        process.terminationHandler = { [weak self] p in
            let code = p.terminationReason == .uncaughtSignal ? -Int(p.terminationStatus) : Int(p.terminationStatus)
            Task { @MainActor in
                self?.running = false
                self?.exitCode = code
            }
        }
        do {
            try process.run()
            running = true
            self.process = process
        } catch {
            output = error.localizedDescription
        }
    }

    /// ponytail: SIGTERM reaches sh and the command it runs, not processes
    /// those start in the background.
    func stop() {
        if process?.isRunning == true { process?.terminate() }
    }
}

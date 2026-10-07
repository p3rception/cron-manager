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

    var id: String {
        switch self {
        case .agent(let a): "agent:\(a?.id ?? "new")"
        case .cron(let j): "cron:\(j.map { String($0.id) } ?? "new")"
        }
    }
}

struct ContentView: View {
    let state: AppState
    @State private var selection: Selection?
    @State private var editing: Editing?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("LaunchAgents") {
                    ForEach(state.agents) { agent in
                        let owner = state.owner(agent)
                        row(agent.label, detail: "\(owner.name), \(state.statusText(agent)), \(agent.schedule)", owner: owner)
                            .tag(Selection.agent(agent.id))
                    }
                }
                Section("Crontab") {
                    ForEach(state.cronJobs) { job in
                        let owner = Owner(command: job.command)
                        row(job.command, detail: "\(owner.name), \(job.summary)\(job.enabled ? "" : ", disabled")", owner: owner)
                            .tag(Selection.cron(job.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .toolbar {
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
                    AgentDetail(state: state, agent: agent) { editing = .agent(agent) }
                }
            case .cron(let id):
                if let job = state.cronJobs.first(where: { $0.id == id }) {
                    CronDetail(state: state, job: job, edit: { editing = .cron(job) }, deleted: { selection = nil })
                }
            case nil:
                Text("Select a job").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { item in
            switch item {
            case .agent(let original):
                AgentEditor(original: original) { plist in
                    try Launchd.save(plist, replacing: original, loaded: original.map(state.isLoaded) ?? false)
                    state.refresh()
                    // A new job is loaded right away, otherwise it would not run until the next login.
                    if original == nil, let agent = state.agents.first(where: { $0.label == plist["Label"] as? String }) {
                        selection = .agent(agent.id)
                        state.perform { try Launchd.load(agent) }
                    }
                }
            case .cron(let original):
                CronEditor(original: original) { job in
                    try state.writeCron { lines in
                        if let original { lines[original.id] = job.line } else { lines.append(job.line) }
                    }
                    if original == nil { selection = .cron(state.cronLines.count - 1) }
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
        } message: {
            Text(state.error ?? "")
        }
    }

    private func row(_ title: String, detail: String, owner: Owner) -> some View {
        HStack {
            OwnerIcon(owner: owner, size: 22)
            VStack(alignment: .leading) {
                Text(title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct AgentDetail: View {
    let state: AppState
    let agent: Agent
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        let loaded = state.isLoaded(agent)
        Form {
            Section {
                OwnerHeader(title: agent.label, owner: state.owner(agent))
            }
            Section {
                LabeledContent("Status", value: state.statusText(agent))
                LabeledContent("Schedule", value: agent.schedule)
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
                    Button("Show Plist in Finder") { NSWorkspace.shared.activateFileViewerSelecting([agent.url]) }
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            ForEach(agent.logPaths, id: \.self) { path in
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
        .formStyle(.grouped)
        .confirmationDialog("Move \(agent.label) to the Trash?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { state.perform { try Launchd.delete(agent, loaded: loaded) } }
        }
    }
}

struct CronDetail: View {
    let state: AppState
    let job: CronJob
    let edit: () -> Void
    let deleted: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                OwnerHeader(title: job.command, owner: Owner(command: job.command))
            }
            Section {
                LabeledContent("Schedule", value: job.summary == job.schedule ? job.schedule : "\(job.summary) (\(job.schedule))")
                LabeledContent("Command") { Text(job.command).textSelection(.enabled) }
                LabeledContent("Status", value: job.enabled ? "enabled" : "disabled")
            }
            Section {
                HStack {
                    Button(job.enabled ? "Disable" : "Enable") {
                        var toggled = job
                        toggled.enabled.toggle()
                        state.perform { try state.writeCron { $0[job.id] = toggled.line } }
                    }
                    Button("Run Now") { state.perform { try Crontab.runNow(job) } }
                    Button("Edit", action: edit)
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this cron job?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                state.perform { try state.writeCron { $0.remove(at: job.id) } }
                deleted()
            }
        }
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

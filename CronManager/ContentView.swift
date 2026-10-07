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
                        row(agent.label, detail: "\(state.statusText(agent)), \(agent.schedule)")
                            .tag(Selection.agent(agent.id))
                    }
                }
                Section("Crontab") {
                    ForEach(state.cronJobs) { job in
                        row(job.command, detail: job.enabled ? job.schedule : "\(job.schedule), disabled")
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
                }
            case .cron(let original):
                CronEditor(original: original) { job in
                    try state.writeCron { lines in
                        if let original { lines[original.id] = job.line } else { lines.append(job.line) }
                    }
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
        } message: {
            Text(state.error ?? "")
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            Section(agent.label) {
                LabeledContent("Status", value: state.statusText(agent))
                LabeledContent("Schedule", value: agent.schedule)
                LabeledContent("Command") { Text(agent.arguments.joined(separator: " ")).textSelection(.enabled) }
                LabeledContent("File") { Text(agent.url.path).textSelection(.enabled) }
            }
            Section {
                HStack {
                    Button(loaded ? "Unload" : "Load") {
                        state.perform { loaded ? try Launchd.unload(agent) : try Launchd.load(agent) }
                    }
                    Button("Run Now") { state.perform { try Launchd.kickstart(agent) } }.disabled(!loaded)
                    Button("Edit", action: edit).disabled(agent.broken)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([agent.url]) }
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            ForEach(agent.logPaths, id: \.self) { path in
                Section(path) {
                    ScrollView {
                        Text(tail(path))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                LabeledContent("Schedule", value: job.schedule)
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

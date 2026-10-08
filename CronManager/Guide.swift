import SwiftUI

// MARK: Content

struct Term: Identifiable {
    let id: String
    let name: String
    let definition: String
}

/// Definitions shown by the (i) buttons, Look Up gestures and the Glossary.
/// Inline Markdown is allowed.
enum Glossary {
    static let terms: [Term] = [
        Term(id: "launchd", name: "launchd",
             definition: "The part of macOS that starts and stops programs, at login, on a schedule or when something happens. It replaces cron on the Mac."),
        Term(id: "launchagent", name: "LaunchAgent",
             definition: "A job launchd runs for you while you are logged in. Each one is a **plist** file in ~/Library/LaunchAgents. Apps and Homebrew add their own here too."),
        Term(id: "launchdaemon", name: "LaunchDaemon",
             definition: "Like a LaunchAgent, but it runs for the whole system, even when nobody is logged in. These live in /Library/LaunchDaemons and need an administrator to change. Cron Manager does not edit them."),
        Term(id: "plist", name: "plist",
             definition: "Property list: Apple's settings file format. Each LaunchAgent is one plist that tells launchd what to run and when. More > View Plist shows the raw file."),
        Term(id: "label", name: "Label",
             definition: "The unique name of a LaunchAgent, written in reverse-domain style such as com.example.backup. launchd and launchctl use it to find the job."),
        Term(id: "load", name: "Load and Unload",
             definition: "**Load** hands a LaunchAgent to launchd so its schedule starts. **Unload** stops it. Cron Manager also disables it so it stays off after the next login. The plist file is kept either way."),
        Term(id: "run-now", name: "Run Now",
             definition: "Starts the job immediately, without waiting for its schedule. For LaunchAgents the output goes to the job's log; for cron jobs a window shows the output live."),
        Term(id: "cron", name: "cron",
             definition: "The classic Unix scheduler. It reads one text file per user, the **crontab**. It runs each line at the times written at its start."),
        Term(id: "crontab", name: "crontab",
             definition: "Your list of cron jobs, one per line: a schedule followed by a shell command. Cron Manager edits it with the crontab command, the same way crontab -e does."),
        Term(id: "cron-syntax", name: "Cron schedule",
             definition: "Five fields: minute, hour, day of month, month and day of week. For example `30 9 * * 1-5` means 09:30 on weekdays. `*` means every, `*/15` every 15 and `1,3` a list."),
        Term(id: "schedule", name: "Schedule",
             definition: "When a job runs. Pick it from the **Repeat** menu: at an interval, hourly, daily, weekly, monthly or at login. Schedules the menu cannot show are kept as they are."),
        Term(id: "interval", name: "Interval",
             definition: "Runs a job every N minutes or hours. In launchd the count starts when the job is loaded; in cron it follows the clock, for example every 15 minutes means :00, :15, :30 and :45."),
        Term(id: "run-at-login", name: "Run at login",
             definition: "Starts the job when you log in and again whenever it is loaded. In the plist this is the RunAtLoad key. For cron jobs the closest match is @reboot, which runs when the Mac starts."),
        Term(id: "keepalive", name: "Kept alive",
             definition: "launchd restarts the program whenever it exits. Used for background helpers that should always run. In the plist this is the KeepAlive key."),
        Term(id: "status", name: "Status",
             definition: "**Running** has a process ID (PID). **Loaded** means launchd follows the schedule but the job is not running right now. **Not loaded** means launchd ignores the plist."),
        Term(id: "exit-code", name: "Exit code",
             definition: "The number a program returns when it ends. 0 means success; anything else is an error. Cron Manager explains the common ones. A negative number means the job was stopped by a signal, such as -9 for killed."),
        Term(id: "next-run", name: "Next run",
             definition: "When the schedule fires next. launchd runs a calendar job missed during sleep when the Mac wakes; cron skips it."),
        Term(id: "last-output", name: "Last output",
             definition: "When the job last wrote to its log. launchd keeps no record of when a job last ran, so the log's date is the closest clue."),
        Term(id: "runs", name: "Runs since loaded",
             definition: "How many times launchd started the job since it was loaded. It resets when the job is loaded again, for example at login."),
        Term(id: "command", name: "Command",
             definition: "What the job runs: a program or script path, optionally with arguments. Shell syntax such as pipes and && works too. Use Choose... to pick a file."),
        Term(id: "log", name: "Log file",
             definition: "A text file that collects what the job prints (stdout) and its errors (stderr). Logs are the first place to look when a job fails. Cron Manager uses ~/Library/Logs unless you pick another folder in Settings."),
        Term(id: "working-folder", name: "Working folder",
             definition: "The folder the job starts in, which matters for scripts that use relative paths. If it does not exist, launchd cannot start the job and reports exit code 78."),
        Term(id: "environment", name: "Environment variables",
             definition: "Settings passed to the program, one NAME=value per line. The most common is **PATH**."),
        Term(id: "path", name: "PATH",
             definition: "The list of folders searched for commands. launchd jobs start with only /usr/bin, /bin, /usr/sbin and /sbin, so tools from Homebrew are not found unless you add them. Use Add Homebrew to PATH in Advanced."),
        Term(id: "homebrew", name: "Homebrew",
             definition: "A package manager for macOS. `brew services` installs LaunchAgents named homebrew.mxcl.<name>. After uninstalling a tool, `brew services cleanup` removes its leftover agent."),
        Term(id: "owner", name: "Owner",
             definition: "The app or tool that added the job, worked out from the plist and the command. Your own scripts show as Your script."),
        Term(id: "enabled", name: "Enabled and disabled",
             definition: "A disabled cron job stays in the crontab as a comment starting with #off, so it can be turned back on. A disabled LaunchAgent is one that was unloaded."),
        Term(id: "backup", name: "Backups",
             definition: "Before each save, Cron Manager copies the previous version to ~/Library/Application Support/CronManager. More > Restore Previous Version swaps it back. Deleted LaunchAgents go to the Trash."),
        Term(id: "attention", name: "Needs attention",
             definition: "Problems that stop a job from running, such as a missing program or log folder, or a failed last run. The warning button in the toolbar shows only these jobs."),
    ]

    static func term(_ id: String) -> Term? { terms.first { $0.id == id } }
}

struct Topic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    /// Paragraphs in inline Markdown. A paragraph starting with "## " is a
    /// heading, one starting with "1. " is a numbered step.
    let body: [String]
}

enum Guide {
    static let glossary = "glossary"

    static let topics: [Topic] = [
        Topic(id: "start", title: "Getting started", symbol: "star", body: [
            "Cron Manager shows the jobs your Mac runs on a schedule and lets you change them without editing files by hand.",
            "## The window",
            "The sidebar lists your **LaunchAgents** and your **crontab** jobs. Each row shows who added the job, its status and its schedule. An orange badge means the job needs attention.",
            "Select a job to see when it runs next, its log and buttons to load, run, edit or delete it. Less common actions are in the **More** menu.",
            "## Learn a word",
            "Click an (i) button next to a word to see what it means. A force click, or a three-finger tap if you use that for Look Up, works on those words too.",
            "## Create your first job",
            "1. Click + in the toolbar and choose New LaunchAgent.",
            "1. Type a name, such as Daily backup.",
            "1. Click Choose... and pick the script to run.",
            "1. Set Repeat to Daily and pick a time.",
            "1. Click Save. The job is loaded right away and its log appears below its details.",
        ]),
        Topic(id: "launchd", title: "launchd and LaunchAgents", symbol: "gearshape.2", body: [
            "**launchd** is the part of macOS that starts programs. A **LaunchAgent** is a small settings file, a plist, in ~/Library/LaunchAgents that tells launchd what to run and when.",
            "Apps add their own LaunchAgents for helpers and updaters. Homebrew adds them for services such as databases. Cron Manager shows who added each one.",
            "## Loading",
            "A LaunchAgent only runs while it is **loaded**. macOS loads every plist in ~/Library/LaunchAgents when you log in. **Load** and **Unload** do the same by hand; Unload also keeps the job off at the next login.",
            "## Editing",
            "When you save changes to a loaded job, Cron Manager reloads it so launchd uses the new settings. Settings the editor does not show are kept as they are.",
        ]),
        Topic(id: "cron", title: "cron and crontab", symbol: "terminal", body: [
            "**cron** is the scheduler from Unix. Your cron jobs live in one text file, the **crontab**, with one job per line: a schedule and a shell command.",
            "`0 0,12 * * * /Users/you/update.sh` runs update.sh at 00:00 and 12:00 every day. Cron Manager shows that as Daily at 00:00 and 12:00, so you do not need to read the syntax.",
            "## Output",
            "Unless a job saves its output to a log, cron mails it to your local mailbox, where it is easy to miss. Turn on **Save output** in the editor to keep a log file instead.",
            "## Disabling",
            "Disable keeps the line in the crontab as a comment starting with #off. Enable removes that prefix again.",
        ]),
        Topic(id: "which", title: "Which one to use", symbol: "arrow.left.arrow.right", body: [
            "Use a **LaunchAgent** for new jobs on a Mac. launchd runs a job missed during sleep when the Mac wakes. It gives each job its own log and settings and can start jobs at login or keep them running.",
            "Use **cron** when the same line has to work on Linux servers too, or for a quick one-line command.",
            "To move a cron job over, select it and choose More > Convert to LaunchAgent. The cron line is disabled, not deleted, so you can switch back.",
        ]),
        Topic(id: "schedules", title: "Schedules", symbol: "calendar", body: [
            "Pick when a job runs from the **Repeat** menu.",
            "**Every few minutes or hours** repeats at an interval. **Hourly** runs at a set minute past each hour. **Daily**, **Weekly** and **Monthly** run at one or more times; use Add Time for more than one.",
            "**At login** runs the job when you log in. For cron jobs this is **At startup**, which runs when the Mac starts.",
            "## Sleep",
            "If the Mac is asleep at the scheduled time, launchd runs the job when it wakes. cron skips that run. Neither runs jobs while the Mac is shut down.",
            "## Custom",
            "Schedules the menu cannot show, such as cron lines with several minutes, stay as they are. Cron jobs can also be edited as raw cron syntax with Custom.",
        ]),
        Topic(id: "logs", title: "Logs and output", symbol: "doc.text", body: [
            "Programs write normal output (stdout) and errors (stderr). Turn on **Save output** to collect both in a log file, under ~/Library/Logs unless you pick another folder in Settings.",
            "The log appears below the job's details and updates every two seconds, so you can watch a job you started with **Run Now**.",
            "**Last output** shows when the log was last written. launchd keeps no record of when a job last ran, so the log's date is the closest clue.",
        ]),
        Topic(id: "fails", title: "When a job fails", symbol: "exclamationmark.triangle", body: [
            "Jobs with an orange badge need attention. Select one to see what is wrong and how to fix it. The warning button in the toolbar shows only those jobs.",
            "## Common causes",
            "1. **Program not found.** The app or tool was removed. Reinstall it, or delete the job.",
            "1. **Command not found (127).** The job's PATH is shorter than Terminal's. Add the tool's folder to PATH in Advanced, or use the full path to the program.",
            "1. **Not executable (126).** Run chmod +x on the script, or start the command with /bin/bash.",
            "1. **Configuration error (78).** launchd could not start the job, usually because the program, the log folder or the working folder is missing.",
            "1. **Permission denied (77 or 1).** macOS may block access to Documents, Desktop or external drives. Give the program, or /usr/sbin/cron for cron jobs, Full Disk Access in System Settings > Privacy & Security.",
            "## Test it",
            "Click **Run Now** and watch the log, or the output window for cron jobs. If the job works in Terminal but not on schedule, the difference is usually PATH or permissions.",
        ]),
        Topic(id: "safety", title: "Undo and safety", symbol: "arrow.uturn.backward", body: [
            "Before every save, Cron Manager keeps the previous version. **More > Restore Previous Version** swaps it back; doing it again switches back to the newer version.",
            "Deleted LaunchAgents go to the Trash. Converting a cron job disables the cron line instead of deleting it.",
            "Cron Manager refuses to save the crontab if it changed outside the app since it was loaded, so edits made in Terminal are not overwritten.",
        ]),
        Topic(id: glossary, title: "Glossary", symbol: "character.book.closed", body: []),
    ]
}

// MARK: Guide window

/// Which topic and term the guide window shows, shared so a popover's
/// Open in Glossary can steer the window.
@MainActor
@Observable
final class GuideState {
    static let shared = GuideState()
    var topic: String? = "start"
    var term: String?
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Cron Manager Guide") { openWindow(id: "guide") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct GuideView: View {
    @State private var state = GuideState.shared

    var body: some View {
        NavigationSplitView {
            List(Guide.topics, selection: $state.topic) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if state.topic == Guide.glossary {
                GlossaryView(highlighted: state.term)
            } else if let topic = Guide.topics.first(where: { $0.id == state.topic }) {
                TopicView(topic: topic)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct TopicView: View {
    let topic: Topic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(topic.title).font(.title2.bold())
                ForEach(Array(topic.body.enumerated()), id: \.offset) { index, paragraph in
                    if paragraph.hasPrefix("## ") {
                        Text(paragraph.dropFirst(3)).font(.headline).padding(.top, 6)
                    } else if paragraph.hasPrefix("1. ") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(stepNumber(at: index)).").monospacedDigit().foregroundStyle(.secondary)
                            markdown(String(paragraph.dropFirst(3)))
                        }
                    } else {
                        markdown(paragraph)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension TopicView {
    /// Steps count from 1 within each run of "1. " paragraphs.
    func stepNumber(at index: Int) -> Int {
        topic.body[...index].reversed().prefix { $0.hasPrefix("1. ") }.count
    }
}

private struct GlossaryView: View {
    let highlighted: String?
    @State private var search = ""

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Glossary.terms.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.definition.localizedStandardContains(search) }) { term in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.name).font(.headline)
                        markdown(term.definition).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(term.id == highlighted ? Color.accentColor.opacity(0.15) : nil)
                    .id(term.id)
                }
            }
            .textSelection(.enabled)
            .searchable(text: $search, prompt: "Search terms")
            .onAppear { if let highlighted { proxy.scrollTo(highlighted, anchor: .top) } }
            .onChange(of: highlighted) { if let highlighted { proxy.scrollTo(highlighted, anchor: .top) } }
        }
        .navigationTitle("Glossary")
    }
}

private func markdown(_ text: String) -> Text {
    Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
}

// MARK: Terms in the app

/// A label with an (i) button. The button, a force click or a Look Up tap
/// on the label opens the term's definition.
struct TermLabel: View {
    let title: String
    let term: String
    @State private var shown = false

    init(_ title: String, term: String) {
        self.title = title
        self.term = term
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button { shown = true } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("What is \(title)?")
            .accessibilityLabel("What is \(title)?")
        }
        .background(LookUpAnchor { shown = true })
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            TermPopover(term: Glossary.term(term) ?? Term(id: term, name: title, definition: ""))
        }
    }
}

private struct TermPopover: View {
    let term: Term
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(term.name).font(.headline)
            markdown(term.definition)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open in Glossary") {
                GuideState.shared.topic = Guide.glossary
                GuideState.shared.term = term.id
                openWindow(id: "guide")
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}

// MARK: Look Up gesture

/// Marks where a term is on screen so a Look Up gesture over it can open the
/// definition. It does not take clicks.
private struct LookUpAnchor: NSViewRepresentable {
    let show: () -> Void

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) { view.show = show }

    final class AnchorView: NSView {
        var show: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { LookUp.shared.add(self) }
        }
    }
}

/// Watches for the Look Up gesture (force click or three-finger tap) and for
/// a deep press. When one lands on a term it opens the definition; anywhere
/// else the event passes on, so the system dictionary still works.
@MainActor
private final class LookUp {
    static let shared = LookUp()
    private let anchors = NSHashTable<LookUpAnchor.AnchorView>.weakObjects()
    private var monitor: Any?
    private var lastStage = 0

    func add(_ anchor: LookUpAnchor.AnchorView) {
        anchors.add(anchor)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [NSEvent.EventTypeMask(type: .quickLook), .pressure]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .pressure {
            defer { lastStage = event.stage }
            // Only the moment a press deepens into a force click counts.
            guard event.stage == 2, lastStage < 2 else { return event }
        }
        for anchor in anchors.allObjects where anchor.window === event.window {
            if anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                anchor.show()
                return nil
            }
        }
        return event
    }
}

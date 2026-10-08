import SwiftUI

/// Creates or edits a LaunchAgent. Keys the form does not show are kept.
/// With `template`, it creates a new job prefilled from that one, for
/// Duplicate and for converting a cron job.
struct AgentEditor: View {
    let original: Agent?
    var template: Agent? = nil
    let save: ([String: Any]) throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var schedule = Schedule()
    @State private var runAtLoad = false
    @State private var logOn = true
    @State private var label = ""
    @State private var stdout = ""
    @State private var stderr = ""
    @State private var workingDirectory = ""
    @State private var environment = ""
    @State private var showAdvanced = false
    @FocusState private var nameFocused: Bool
    @AppStorage(Defaults.labelPrefixKey) private var labelPrefix = Defaults.labelPrefix
    @AppStorage(Defaults.logFolderKey) private var logFolder = Defaults.logFolder
    @AppStorage(Defaults.saveOutputKey) private var saveOutput = true

    private var slug: String {
        slugify(name)
    }
    private var effectiveLabel: String {
        guard label.isEmpty else { return label }
        let prefix = labelPrefix.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return prefix.isEmpty ? slug : "\(prefix).\(slug)"
    }
    private var defaultLog: String {
        let file = !slug.isEmpty ? slug : label.isEmpty ? "name" : label
        return logFolder + "/\(file).log"
    }
    /// New jobs log to the default path until a path is typed in.
    private func logPath(_ field: String) -> String { field.isEmpty && original == nil ? defaultLog : field }

    var body: some View {
        EditorSheet(submit: submit) {
            Section {
                if original == nil {
                    TextField("Name", text: $name, prompt: Text("Daily backup"))
                        .focused($nameFocused)
                }
                CommandField(command: $command)
            }
            ScheduleFields(schedule: $schedule, cron: false,
                           keepsCustom: source.map { Schedule(plist: $0.plist).kind == .custom } ?? false)
            Section {
                Toggle(isOn: Binding(get: { logOn }, set: { on in
                    logOn = on
                    if on, original != nil, stdout.isEmpty, stderr.isEmpty { stdout = defaultLog; stderr = defaultLog }
                })) {
                    TermLabel("Save output to \(((logPath(stdout).isEmpty ? defaultLog : logPath(stdout)) as NSString).abbreviatingWithTildeInPath)", term: "log")
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    LabeledContent {
                        TextField("Label", text: $label, prompt: Text(effectiveLabel)).labelsHidden()
                    } label: { TermLabel("Label", term: "label") }
                    if schedule.kind != .atLogin {
                        Toggle(isOn: $runAtLoad) { TermLabel("Also run at login", term: "run-at-login") }
                    }
                    if logOn {
                        TextField("Output log", text: $stdout, prompt: Text(defaultLog))
                        TextField("Error log", text: $stderr, prompt: Text(defaultLog))
                    }
                    LabeledContent {
                        TextField("Working folder", text: $workingDirectory, prompt: Text("/")).labelsHidden()
                    } label: { TermLabel("Working folder", term: "working-folder") }
                    LabeledContent {
                        VStack(alignment: .trailing) {
                            TextEditor(text: $environment)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
                                Button("Add Homebrew to PATH", action: addHomebrewPath).controlSize(.small)
                            }
                        }
                    } label: { TermLabel("Environment", term: "environment") }
                    Text("One NAME=value per line. launchd starts jobs with PATH=/usr/bin:/bin:/usr/sbin:/sbin, so tools from Homebrew are not found unless PATH is set here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        nameFocused = original == nil
        guard let source else { logOn = saveOutput; return }
        let p = source.plist
        label = source.label
        command = commandLine(source.arguments)
        schedule = Schedule(plist: p)
        if schedule.kind == .custom { schedule.custom = source.rawSchedule }
        runAtLoad = schedule.kind != .atLogin && p["RunAtLoad"] as? Bool == true
        stdout = p["StandardOutPath"] as? String ?? ""
        stderr = p["StandardErrorPath"] as? String ?? ""
        logOn = !stdout.isEmpty || !stderr.isEmpty
        workingDirectory = p["WorkingDirectory"] as? String ?? ""
        environment = (p["EnvironmentVariables"] as? [String: String] ?? [:])
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        showAdvanced = !workingDirectory.isEmpty || !environment.isEmpty
    }

    /// Puts Homebrew in front of launchd's default PATH, replacing any PATH line.
    private func addHomebrewPath() {
        let path = "PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        let others = environment.split(separator: "\n").filter { !$0.hasPrefix("PATH=") }.map(String.init)
        environment = ([path] + others).joined(separator: "\n")
    }

    private func parseEnvironment() throws -> [String: String] {
        var result: [String: String] = [:]
        for line in environment.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            guard let eq = line.firstIndex(of: "="), line[..<eq].wholeMatch(of: #/[A-Za-z_][A-Za-z0-9_]*/#) != nil else {
                throw AppError("\"\(line)\" is not NAME=value.")
            }
            result[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return result
    }

    private var source: Agent? { original ?? template }

    private func submit() throws {
        try save(build())
        dismiss()
    }

    private func build() throws -> [String: Any] {
        guard original != nil || !slug.isEmpty || !label.isEmpty else { throw AppError("Enter a name.") }
        let line = command.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { throw AppError("Enter a command.") }
        let argv = argumentList(line, original: source?.arguments)
        if argv != source?.arguments, !isShellCommand(argv), !FileManager.default.isExecutableFile(atPath: argv[0]) {
            throw AppError("\(argv[0]) is not executable. Run chmod +x on it, or start the command with /bin/bash.")
        }
        if schedule.kind == .weekly, schedule.weekdays.isEmpty { throw AppError("Pick at least one day.") }

        var p = source?.plist ?? [:]
        p["Label"] = effectiveLabel
        if argv != source?.arguments {
            p["ProgramArguments"] = argv
            // Program would override argv[0].
            p["Program"] = nil
        }
        schedule.apply(to: &p)
        if schedule.kind != .atLogin {
            if runAtLoad { p["RunAtLoad"] = true } else { p["RunAtLoad"] = nil }
        }
        for (key, field) in [("StandardOutPath", stdout), ("StandardErrorPath", stderr)] {
            if logOn, !logPath(field).isEmpty { p[key] = logPath(field) } else { p[key] = nil }
        }
        let folder = workingDirectory.trimmingCharacters(in: .whitespaces)
        if folder.isEmpty {
            p["WorkingDirectory"] = nil
        } else {
            // launchd fails with exit 78 when it cannot change to this folder.
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
                throw AppError("The working folder \(folder) does not exist.")
            }
            p["WorkingDirectory"] = folder
        }
        let env = try parseEnvironment()
        if env.isEmpty { p["EnvironmentVariables"] = nil } else { p["EnvironmentVariables"] = env }
        return p
    }
}

struct CronEditor: View {
    let original: CronJob?
    /// Prefills a new job, for Duplicate.
    var template: CronJob? = nil
    let save: (CronJob) throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var command = ""
    @State private var schedule = Schedule()
    @State private var enabled = true
    @State private var logOn = true
    @State private var log = ""

    /// <log folder>/<script name>.log, from the command's first word.
    private var defaultLog: String {
        let first = command.split(separator: " ").first.map { (String($0) as NSString).lastPathComponent } ?? ""
        let name = slugify((first as NSString).deletingPathExtension)
        return logFolder + "/\(name.isEmpty ? "cron-job" : name).log"
    @AppStorage(Defaults.logFolderKey) private var logFolder = Defaults.logFolder
    @AppStorage(Defaults.saveOutputKey) private var saveOutput = true
    }

    var body: some View {
        EditorSheet(submit: submit) {
            Section {
                CommandField(command: $command, autofocus: original == nil)
                Toggle(isOn: $enabled) { TermLabel("Enabled", term: "enabled") }
            }
            ScheduleFields(schedule: $schedule, cron: true)
            Section {
                Toggle(isOn: $logOn) {
                    TermLabel("Save output to \(((log.isEmpty ? defaultLog : log) as NSString).abbreviatingWithTildeInPath)", term: "log")
                }
                if logOn {
                    TextField("Log file", text: $log, prompt: Text(defaultLog))
                }
            } footer: {
                Text("Without a log, cron mails the output to your local mailbox, where it is easy to miss.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard let source = original ?? template else { logOn = saveOutput; return }
            command = source.baseCommand
            schedule = Schedule(cron: source.schedule)
            enabled = source.enabled
            log = source.logPath ?? ""
            logOn = source.logPath != nil
        }
    }

    private func submit() throws {
        let base = command.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !base.contains("\n") else { throw AppError("Enter a one-line command.") }
        let logFile = log.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLog : (log as NSString).expandingTildeInPath
        if logOn, !FileManager.default.fileExists(atPath: (logFile as NSString).deletingLastPathComponent) {
            throw AppError("The folder for \(logFile) does not exist.")
        }
        let job = CronJob(id: original?.id ?? -1,
                          schedule: schedule.cronExpression,
                          command: CronJob.command(base, log: logOn ? logFile : nil),
                          enabled: enabled)
        guard job.hasValidShape else { throw AppError("A cron schedule needs five fields or one @keyword.") }
        if schedule.kind == .weekly, schedule.weekdays.isEmpty { throw AppError("Pick at least one day.") }
        if let problem = schedule.cronProblem { throw AppError(problem) }
        try save(job)
        dismiss()
    }
}

/// The form, error line and Cancel / Save buttons both editors share.
private struct EditorSheet<Content: View>: View {
    let submit: () throws -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                content
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try submit() } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500)
    }
}

/// A shell command, with a button that fills in the path of a chosen file.
struct CommandField: View {
    @Binding var command: String
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            HStack {
                TextField("Command", text: $command, prompt: Text("/path/to/script.sh"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                Button("Choose...", action: choose)
            }
        } label: { TermLabel("Command", term: "command") }
        .onAppear { focused = autofocus }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.message = "Choose a script, program or app to run"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // An app runs through its executable, which keeps the job tied to the app.
        let path = url.pathExtension == "app" ? Bundle(url: url)?.executablePath ?? url.path : url.path
        command = shellQuote(path)
    }
}

struct ScheduleFields: View {
    @Binding var schedule: Schedule
    let cron: Bool
    /// launchd has no raw schedule field; Custom only keeps an existing
    /// schedule the editor cannot show.
    var keepsCustom = false

    private var login: String { cron ? "At startup" : "At login" }

    var body: some View {
        Section {
            Picker(selection: $schedule.kind) {
                ForEach(Schedule.Kind.allCases.filter { $0 != .custom || cron || keepsCustom }, id: \.self) { kind in
                    Text(title(kind))
                }
            } label: { TermLabel("Repeat", term: "schedule") }
            switch schedule.kind {
            case .interval:
                LabeledContent("Every") {
                    HStack {
                        Picker("Every", selection: $schedule.every) {
                            ForEach(Schedule.choices[schedule.unit]!, id: \.self) { Text("\($0)") }
                        }
                        Picker("Unit", selection: $schedule.unit) {
                            ForEach(Schedule.Unit.allCases, id: \.self) { Text($0.rawValue) }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            case .hourly:
                Picker("At minute", selection: $schedule.minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: ":%02d", $0)) }
                }
            case .daily:
                timePicker
            case .weekly:
                LabeledContent("On") { DayToggles(days: $schedule.weekdays) }
                timePicker
            case .monthly:
                Picker("Day", selection: $schedule.day) {
                    ForEach(1...31, id: \.self) { Text("\($0)") }
                }
                timePicker
            case .atLogin:
                EmptyView()
            case .custom:
                if cron {
                    LabeledContent {
                        TextField("Cron schedule", text: $schedule.custom, prompt: Text("0 0,12 * * *"))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                    } label: { TermLabel("Cron schedule", term: "cron-syntax") }
                }
            }
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: schedule.unit) {
            if !Schedule.choices[schedule.unit]!.contains(schedule.every) { schedule.every = 1 }
        }
        .onChange(of: schedule.kind) { old, new in
            // Start a custom cron schedule from what was picked before.
            if new == .custom, schedule.custom.isEmpty {
                var previous = schedule
                previous.kind = old
                schedule.custom = previous.cronExpression
            }
        }
    }

    private var footer: String {
        guard schedule.kind == .custom else { return "Runs \(schedule.summary(login: login.lowercased()))." }
        return cron
            ? "Minute, hour, day of month, month, day of week."
            : "Current schedule: \(schedule.custom). Kept as is."
    }

    /// One picker per run time, with remove buttons and Add Time.
    private var timePicker: some View {
        LabeledContent("At") {
            VStack(alignment: .trailing) {
                ForEach(schedule.times.indices, id: \.self) { i in
                    HStack {
                        DatePicker("Time \(i + 1)", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: schedule.times[i].hour, minute: schedule.times[i].minute, second: 0, of: .now) ?? .now },
                            set: {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                schedule.times[i] = .init(hour: c.hour ?? 0, minute: c.minute ?? 0)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        Button {
                            schedule.times.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(schedule.times.count == 1)
                        .help("Remove this time")
                        .accessibilityLabel("Remove time \(i + 1)")
                    }
                }
                Button("Add Time") {
                    // Same minutes, so the new time also works for cron.
                    let last = schedule.times.last ?? .init(hour: 9, minute: 0)
                    schedule.times.append(.init(hour: (last.hour + 1) % 24, minute: last.minute))
                }
                .controlSize(.small)
            }
        }
    }

    private func title(_ kind: Schedule.Kind) -> String {
        switch kind {
        case .interval: "Every few minutes or hours"
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .atLogin: login
        case .custom: cron ? "Custom (cron syntax)" : "Unchanged"
        }
    }
}

/// Weekday buttons in the user's locale order (Monday first in most of Europe).
struct DayToggles: View {
    @Binding var days: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let day = (i + calendar.firstWeekday - 1) % 7
                Toggle(calendar.veryShortWeekdaySymbols[day], isOn: Binding(
                    get: { days.contains(day) },
                    set: { if $0 { days.insert(day) } else { days.remove(day) } }
                ))
                .toggleStyle(.button)
                .help(calendar.weekdaySymbols[day])
                .accessibilityLabel(calendar.weekdaySymbols[day])
            }
        }
    }
}

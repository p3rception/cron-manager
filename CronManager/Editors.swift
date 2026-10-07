import SwiftUI

/// Creates or edits a LaunchAgent. Keys the form does not show are kept.
struct AgentEditor: View {
    let original: Agent?
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
    @FocusState private var nameFocused: Bool

    private var slug: String {
        slugify(name)
    }
    private var effectiveLabel: String { label.isEmpty ? "com.\(NSUserName()).\(slug)" : label }
    /// launchd does not expand ~, so log paths are absolute.
    private var defaultLog: String {
        let file = !slug.isEmpty ? slug : label.isEmpty ? "name" : label
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/\(file).log"
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
                           keepsCustom: original.map { Schedule(plist: $0.plist).kind == .custom } ?? false)
            Section {
                Toggle(isOn: Binding(get: { logOn }, set: { on in
                    logOn = on
                    if on, original != nil, stdout.isEmpty, stderr.isEmpty { stdout = defaultLog; stderr = defaultLog }
                })) {
                    Text("Save output to \((logPath(stdout) as NSString).abbreviatingWithTildeInPath)")
                }
                DisclosureGroup("Advanced") {
                    TextField("Label", text: $label, prompt: Text(effectiveLabel))
                    if schedule.kind != .atLogin {
                        Toggle("Also run at login", isOn: $runAtLoad)
                    }
                    if logOn {
                        TextField("Output log", text: $stdout, prompt: Text(defaultLog))
                        TextField("Error log", text: $stderr, prompt: Text(defaultLog))
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let original else { return nameFocused = true }
        let p = original.plist
        label = original.label
        command = commandLine(original.arguments)
        schedule = Schedule(plist: p)
        if schedule.kind == .custom { schedule.custom = original.rawSchedule }
        runAtLoad = schedule.kind != .atLogin && p["RunAtLoad"] as? Bool == true
        stdout = p["StandardOutPath"] as? String ?? ""
        stderr = p["StandardErrorPath"] as? String ?? ""
        logOn = !stdout.isEmpty || !stderr.isEmpty
    }

    private func submit() throws {
        try save(build())
        dismiss()
    }

    private func build() throws -> [String: Any] {
        guard original != nil || !slug.isEmpty || !label.isEmpty else { throw AppError("Enter a name.") }
        let line = command.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { throw AppError("Enter a command.") }
        let argv = argumentList(line, original: original?.arguments)
        if argv != original?.arguments, !isShellCommand(argv), !FileManager.default.isExecutableFile(atPath: argv[0]) {
            throw AppError("\(argv[0]) is not executable. Run chmod +x on it, or start the command with /bin/bash.")
        }
        if schedule.kind == .weekly, schedule.weekdays.isEmpty { throw AppError("Pick at least one day.") }

        var p = original?.plist ?? [:]
        p["Label"] = effectiveLabel
        if argv != original?.arguments {
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
        return p
    }
}

struct CronEditor: View {
    let original: CronJob?
    let save: (CronJob) throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var command = ""
    @State private var schedule = Schedule()
    @State private var enabled = true

    var body: some View {
        EditorSheet(submit: submit) {
            Section {
                CommandField(command: $command, autofocus: original == nil)
                Toggle("Enabled", isOn: $enabled)
            }
            ScheduleFields(schedule: $schedule, cron: true)
        }
        .onAppear {
            guard let original else { return }
            command = original.command
            schedule = Schedule(cron: original.schedule)
            enabled = original.enabled
        }
    }

    private func submit() throws {
        let job = CronJob(id: original?.id ?? -1,
                          schedule: schedule.cronExpression,
                          command: command.trimmingCharacters(in: .whitespaces),
                          enabled: enabled)
        guard !job.command.isEmpty, !job.command.contains("\n") else { throw AppError("Enter a one-line command.") }
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
        LabeledContent("Command") {
            HStack {
                TextField("Command", text: $command, prompt: Text("/path/to/script.sh"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                Button("Choose...", action: choose)
            }
        }
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
            Picker("Repeat", selection: $schedule.kind) {
                ForEach(Schedule.Kind.allCases.filter { $0 != .custom || cron || keepsCustom }, id: \.self) { kind in
                    Text(title(kind))
                }
            }
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
                    TextField("Cron schedule", text: $schedule.custom, prompt: Text("0 0,12 * * *"))
                        .font(.system(.body, design: .monospaced))
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

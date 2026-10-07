import SwiftUI

/// Edits the common LaunchAgent keys. Keys the form does not show are kept.
struct AgentEditor: View {
    let original: Agent?
    let save: ([String: Any]) throws -> Void
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable {
        case none = "None", interval = "Every N seconds", calendar = "Calendar"
    }
    static let calendarKeys = ["Minute", "Hour", "Day", "Weekday", "Month"]

    @State private var label = ""
    @State private var arguments = ""
    @State private var kind = Kind.none
    @State private var interval = ""
    @State private var calendar: [String: String] = [:]
    @State private var runAtLoad = false
    @State private var stdout = ""
    @State private var stderr = ""
    @State private var message: String?

    /// A StartCalendarInterval the form cannot represent is left untouched.
    private var scheduleLocked: Bool {
        guard let original else { return false }
        return original.plist["StartCalendarInterval"] != nil && original.calendar == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Label", text: $label, prompt: Text("com.example.job"))
                LabeledContent("Arguments") {
                    TextEditor(text: $arguments)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                }
                Text("One argument per line, program first.").font(.caption).foregroundStyle(.secondary)
                Picker("Schedule", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .disabled(scheduleLocked)
                if scheduleLocked {
                    Text("This job has several calendar entries. They are kept unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if kind == .interval {
                    TextField("Seconds", text: $interval)
                } else if kind == .calendar {
                    ForEach(Self.calendarKeys, id: \.self) { key in
                        TextField(key, text: Binding(get: { calendar[key] ?? "" }, set: { calendar[key] = $0 }),
                                  prompt: Text("any"))
                    }
                }
                Toggle("Run at load", isOn: $runAtLoad)
                TextField("Stdout log", text: $stdout, prompt: Text("/tmp/job.log"))
                TextField("Stderr log", text: $stderr, prompt: Text("/tmp/job.log"))
                if let message { Text(message).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { submit() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private func load() {
        guard let original else { return }
        let p = original.plist
        label = original.label
        arguments = original.arguments.joined(separator: "\n")
        runAtLoad = p["RunAtLoad"] as? Bool ?? false
        stdout = p["StandardOutPath"] as? String ?? ""
        stderr = p["StandardErrorPath"] as? String ?? ""
        if let n = p["StartInterval"] as? Int {
            kind = .interval
            interval = String(n)
        } else if let cal = original.calendar {
            kind = .calendar
            calendar = cal.mapValues(String.init)
        }
    }

    private func submit() {
        do {
            try save(build())
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func build() throws -> [String: Any] {
        var p = original?.plist ?? [:]
        let argv = arguments.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !argv.isEmpty else { throw AppError("Add at least the program path.") }
        p["Label"] = label
        p["ProgramArguments"] = argv
        // Program would override argv[0], so the form's arguments are the only source.
        p["Program"] = nil
        if runAtLoad { p["RunAtLoad"] = true } else { p["RunAtLoad"] = nil }
        if stdout.isEmpty { p["StandardOutPath"] = nil } else { p["StandardOutPath"] = stdout }
        if stderr.isEmpty { p["StandardErrorPath"] = nil } else { p["StandardErrorPath"] = stderr }
        if !scheduleLocked {
            p["StartInterval"] = nil
            p["StartCalendarInterval"] = nil
            switch kind {
            case .none: break
            case .interval:
                guard let n = Int(interval), n > 0 else { throw AppError("Seconds must be a positive number.") }
                p["StartInterval"] = n
            case .calendar:
                var dict: [String: Int] = [:]
                for (key, value) in calendar where !value.isEmpty {
                    guard let n = Int(value) else { throw AppError("\(key) must be a number.") }
                    dict[key] = n
                }
                p["StartCalendarInterval"] = dict
            }
        }
        return p
    }
}

struct CronEditor: View {
    let original: CronJob?
    let save: (CronJob) throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var schedule = ""
    @State private var command = ""
    @State private var enabled = true
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Schedule", text: $schedule, prompt: Text("0 * * * *"))
                Text("Minute, hour, day of month, month, day of week. Or @hourly, @daily, @weekly, @monthly, @reboot.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Command", text: $command, prompt: Text("/path/to/script.sh"))
                Toggle("Enabled", isOn: $enabled)
                if let message { Text(message).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { submit() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear {
            guard let original else { return }
            schedule = original.schedule
            command = original.command
            enabled = original.enabled
        }
    }

    private func submit() {
        let job = CronJob(id: original?.id ?? -1,
                          schedule: schedule.trimmingCharacters(in: .whitespaces),
                          command: command.trimmingCharacters(in: .whitespaces),
                          enabled: enabled)
        guard job.hasValidShape else { return message = "The schedule needs five fields or one @keyword." }
        guard !job.command.isEmpty, !job.command.contains("\n") else { return message = "Enter a one-line command." }
        do {
            try save(job)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

import SwiftUI

/// UserDefaults keys and default values for the Settings window.
enum Defaults {
    static let appearanceKey = "appearance"
    static let labelPrefixKey = "labelPrefix"
    static let logFolderKey = "logFolder"
    static let saveOutputKey = "saveOutput"

    static let labelPrefix = "com.\(NSUserName())"
    /// launchd does not expand ~, so the folder is stored as an absolute path.
    static let logFolder = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs"
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage(Defaults.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Defaults.labelPrefixKey) private var labelPrefix = Defaults.labelPrefix
    @AppStorage(Defaults.logFolderKey) private var logFolder = Defaults.logFolder
    @AppStorage(Defaults.saveOutputKey) private var saveOutput = true

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
            Section {
                LabeledContent {
                    TextField("Label prefix", text: $labelPrefix).labelsHidden()
                } label: { TermLabel("Label prefix", term: "label") }
                LabeledContent {
                    HStack {
                        Text((logFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose...", action: chooseLogFolder)
                    }
                } label: { TermLabel("Log folder", term: "log") }
                Toggle("Save output by default", isOn: $saveOutput)
            } header: {
                Text("New jobs")
            } footer: {
                Text("Existing jobs keep their label and log.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 400)
        .fixedSize()
        .onChange(of: appearance) { appearance.apply() }
    }

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder new jobs save their output to"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: logFolder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        logFolder = url.path
    }
}

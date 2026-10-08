import SwiftUI

enum Appearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"

    func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 400)
        .fixedSize()
        .onChange(of: appearance) { appearance.apply() }
    }
}

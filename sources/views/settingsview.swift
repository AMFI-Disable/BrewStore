import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: HomebrewManager

    var body: some View {
        Form {
            Section("Homebrew") {
                LabeledContent("Detected path", value: manager.brewPath ?? "Not installed")
                Button("Re-detect Homebrew", action: manager.detectHomebrew)
            }
            Section("Product") {
                LabeledContent("Version", value: "1.0.0")
                Text("BrewStore is a focused Homebrew package manager. Brewfile sync and analytics are planned for a later release.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Settings")
    }
}

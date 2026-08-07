import SwiftUI

struct HomebrewSetupView: View {
    @ObservedObject var manager: HomebrewManager
    @State private var showingConfirmation = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Homebrew is required")
                .font(.title.bold())
            Text("BrewStore uses the official Homebrew command-line tools to install, update, and remove packages. You can browse settings now, or install Homebrew with an explicit confirmation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 540)
            Link("Read the official Homebrew documentation", destination: URL(string: "https://brew.sh")!)
            Button("Install Homebrew") { showingConfirmation = true }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isBootstrapping)
            if !manager.statusMessage.isEmpty { Text(manager.statusMessage).font(.callout).foregroundStyle(.secondary) }
            if let error = manager.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if !manager.outputLog.isEmpty {
                TextEditor(text: .constant(manager.outputLog))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 220)
                    .border(Color.secondary.opacity(0.25))
                    .textSelection(.enabled)
            }
        }
        .padding(40)
        .confirmationDialog("Install Homebrew?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Install from the official Homebrew source") { manager.bootstrapHomebrew() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BrewStore will run the official installer and may ask for your administrator password. The installer runs with visible output and can be cancelled.")
        }
    }
}

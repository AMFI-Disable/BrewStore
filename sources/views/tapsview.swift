import SwiftUI

struct TapsView: View {
    @ObservedObject var manager: HomebrewManager
    @State private var newTap = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Taps").font(.largeTitle.bold())
                    Text("Manage additional Homebrew repositories.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", action: manager.refresh)
            }
            .padding()
            HStack {
                TextField("user/repository", text: $newTap)
                    .textFieldStyle(.roundedBorder)
                Button("Add Tap") {
                    let value = newTap.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return }
                    manager.addTap(value)
                    newTap = ""
                }
                .disabled(manager.isOperating)
            }
            .padding(.horizontal)
            List(manager.taps) { tap in
                HStack {
                    Label(tap.name, systemImage: "square.3.layers.3d.down.forward")
                    Spacer()
                    Button("Remove", role: .destructive) { manager.removeTap(tap) }
                        .disabled(manager.isOperating)
                }
            }
        }
    }
}

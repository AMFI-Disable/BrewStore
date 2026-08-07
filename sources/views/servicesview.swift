import SwiftUI

struct ServicesView: View {
    @ObservedObject var manager: HomebrewManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Services").font(.largeTitle.bold())
                    Text("Manage Homebrew background services.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", action: manager.refresh)
            }
            .padding()
            List(manager.services) { service in
                HStack {
                    VStack(alignment: .leading) {
                        Text(service.name).font(.headline)
                        Text([service.status, service.user, service.file].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Actions") {
                        Button("Start") { manager.perform(service: service, action: .start) }
                        Button("Restart") { manager.perform(service: service, action: .restart) }
                        Button("Stop") { manager.perform(service: service, action: .stop) }
                    }
                    .disabled(manager.isOperating)
                }
            }
            .overlay { if manager.services.isEmpty && !manager.isLoading { ContentUnavailableView("No services", systemImage: "gearshape.2", description: Text("Install a Homebrew service to manage it here.")) } }
        }
    }
}

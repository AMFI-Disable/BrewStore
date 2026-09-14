import AppKit
import SwiftUI

struct ServicesView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var telemetry = BrewStoreServiceTelemetryMonitor()
    @StateObject private var watchdog = BrewStoreServiceWatchdog.shared
    @ObservedObject private var backgroundManager = BrewStoreBackgroundItemsManager.shared

    @State private var serviceCategoryTab: Int = 0
    @State private var search = ""
    @State private var backgroundSearch = ""
    @State private var selectedLogService: BrewStoreService?
    @State private var pendingAction: PendingServiceAction?
    @State private var itemPendingTrash: BrewStoreBackgroundItem?

    enum PendingServiceAction: Identifiable {
        case single(service: BrewStoreService, action: ServiceActionType)
        case batchStart
        case batchStop
        case batchRestart
        case autoFixErrored([BrewStoreService])

        var id: String {
            switch self {
            case let .single(svc, act): "single-\(svc.id)-\(act)"
            case .batchStart: "batchStart"
            case .batchStop: "batchStop"
            case .batchRestart: "batchRestart"
            case .autoFixErrored: "autoFixErrored"
            }
        }
    }

    enum ServiceActionType {
        case start, stop, restart
    }

    private var erroredServices: [BrewStoreService] {
        manager.services.filter(\.isError)
    }

    private var filteredServices: [BrewStoreService] {
        if search.isEmpty {
            return manager.services
        }
        return manager.services.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
                $0.status.localizedCaseInsensitiveContains(search) ||
                ($0.user?.localizedCaseInsensitiveContains(search) == true)
        }
    }

    private var filteredBackgroundItems: [BrewStoreBackgroundItem] {
        if backgroundSearch.isEmpty {
            return backgroundManager.items
        }
        let q = backgroundSearch.lowercased()
        return backgroundManager.items.filter {
            $0.displayName.lowercased().contains(q) ||
                $0.label.lowercased().contains(q) ||
                ($0.associatedAppName?.lowercased().contains(q) == true)
        }
    }

    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Standalone Header
            if showHeader {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Services & Daemons").font(.largeTitle.bold())
                        Text("Manage Homebrew background services, macOS launch agents, and startup daemons.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if serviceCategoryTab == 0 {
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(watchdog.isWatchdogEnabled ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(watchdog.isWatchdogEnabled ? "Monitoring Active" : "Monitoring Inactive")
                                .font(.caption2.bold())
                        }
                        .brewPillStyle()

                        batchControlsMenu

                        Button {
                            manager.refresh()
                            telemetry.refreshTelemetry(for: manager.services)
                        } label: {
                            Label(telemetry.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(manager.isLoading || manager.isOperating || telemetry.isRefreshing)
                    } else {
                        Button {
                            backgroundManager.scanBackgroundItems()
                        } label: {
                            Label(backgroundManager.isScanning ? "Scanning…" : "Scan Agents", systemImage: "arrow.clockwise")
                        }
                        .disabled(backgroundManager.isScanning)
                    }
                }
                .padding()
            }

            // Sub-category Navigation & Compact Actions Bar
            HStack(spacing: Spacing.md) {
                Picker("", selection: $serviceCategoryTab) {
                    Text("Homebrew Daemons (\(manager.services.count))").tag(0)
                    Text("macOS LaunchAgents & Login Items (\(backgroundManager.items.count))").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if !showHeader {
                    if serviceCategoryTab == 0 {
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(watchdog.isWatchdogEnabled ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(watchdog.isWatchdogEnabled ? "Monitoring Active" : "Monitoring Inactive")
                                .font(.caption2.bold())
                        }
                        .brewPillStyle()

                        batchControlsMenu

                        Button {
                            manager.refresh()
                            telemetry.refreshTelemetry(for: manager.services)
                        } label: {
                            Label(telemetry.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(manager.isLoading || manager.isOperating || telemetry.isRefreshing)
                    } else {
                        Button {
                            backgroundManager.scanBackgroundItems()
                        } label: {
                            Label(backgroundManager.isScanning ? "Scanning…" : "Scan Agents", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(backgroundManager.isScanning)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, showHeader ? 0 : Spacing.sm)
            .padding(.bottom, Spacing.sm)

            Divider()

            Group {
                if serviceCategoryTab == 1 {
                    macOSBackgroundItemsView
                } else {
                    homebrewServicesView
                }
            }
            .id(serviceCategoryTab)
            .animation(nil, value: serviceCategoryTab)
        }
        .sheet(item: $selectedLogService) { svc in
            ServiceLogView(service: svc, brewPrefix: manager.brewPrefix)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pendingAction != nil }, set: {
                if !$0 {
                    pendingAction = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                switch action {
                case let .single(svc, type):
                    Button(
                        type == .stop ? "Stop Service" : (type == .restart ? "Restart Service" : "Start Service"),
                        role: type == .stop ? .destructive : nil
                    ) {
                        manager.perform(
                            service: svc,
                            action: type == .stop ? .stop : (type == .restart ? .restart : .start)
                        )
                        pendingAction = nil
                    }
                case .batchStart:
                    Button("Start All Stopped Daemons") {
                        let stopped = manager.services.filter { !$0.isRunning }
                        manager.batchPerform(services: stopped, action: .start)
                        pendingAction = nil
                    }
                case .batchStop:
                    Button("Stop All Running Daemons", role: .destructive) {
                        let running = manager.services.filter { $0.isRunning }
                        manager.batchPerform(services: running, action: .stop)
                        pendingAction = nil
                    }
                case .batchRestart:
                    Button("Restart All Active Daemons") {
                        let running = manager.services.filter { $0.isRunning }
                        manager.batchPerform(services: running, action: .restart)
                        pendingAction = nil
                    }
                case let .autoFixErrored(svcs):
                    let title = svcs.count == 1
                        ? "Restart \(svcs.first?.name ?? "Service")"
                        : "Restart \(svcs.count) Errored Services"
                    Button(title) {
                        manager.batchPerform(services: svcs, action: .restart)
                        pendingAction = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            "Move '\(itemPendingTrash?.displayName ?? "")' to Trash?",
            isPresented: Binding(get: { itemPendingTrash != nil }, set: {
                if !$0 {
                    itemPendingTrash = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let item = itemPendingTrash {
                Button("Move to Trash", role: .destructive) {
                    backgroundManager.trashItem(item)
                    itemPendingTrash = nil
                }
                Button("Cancel", role: .cancel) {
                    itemPendingTrash = nil
                }
            }
        } message: {
            if let item = itemPendingTrash {
                Text("This will stop the daemon and safely move '\(item.plistURL?.lastPathComponent ?? "plist")' to ~/.Trash.")
            }
        }
        .onAppear {
            telemetry.refreshTelemetry(for: manager.services)
            backgroundManager.scanBackgroundItems()
        }
        .onChange(of: manager.services) { _, newServices in
            telemetry.refreshTelemetry(for: newServices)
        }
    }

    @ViewBuilder
    private var batchControlsMenu: some View {
        Menu {
            Button {
                pendingAction = .batchStart
            } label: {
                Label("Start All Stopped Daemons", systemImage: "play.fill")
            }

            Button {
                pendingAction = .batchStop
            } label: {
                Label("Stop All Running Daemons", systemImage: "stop.fill")
            }

            Button {
                pendingAction = .batchRestart
            } label: {
                Label("Restart All Active Daemons", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Batch Controls", systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(manager.isLoading || manager.isOperating)
    }

    private var homebrewServicesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrewStoreSectionSearchBar(
                    text: $search,
                    placeholder: "Search background services (e.g. nginx, redis, postgresql)…",
                    count: filteredServices.count
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            BrewStoreLockBanner(manager: manager)

            if !erroredServices.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(erroredServices.count) Service\(erroredServices.count == 1 ? "" : "s") in Error State")
                            .font(.subheadline.bold())
                        Text("Detected error state: \(erroredServices.map(\.name).joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        pendingAction = .autoFixErrored(erroredServices)
                    } label: {
                        if erroredServices.count == 1, let single = erroredServices.first {
                            Label("Review Repair for \(single.name)", systemImage: "bolt.fill")
                        } else {
                            Label("Review Repair (\(erroredServices.count) Services)", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if let error = manager.errorMessage {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else if manager.isOperating, let op = manager.activeOperationTitle {
                HStack {
                    Text(op)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            List(filteredServices) { service in
                let metric = telemetry.metrics[service.name]

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(service.isRunning ? Color.green : (service.isError ? Color.red : Color.secondary.opacity(0.5)))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(service.name).font(.headline)
                                Text(service.status)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        (service.isRunning ? Color.green : Color.secondary).opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(service.isRunning ? .green : .secondary)

                                if service.isRunning, let port = metric?.listeningPort {
                                    HStack(spacing: 3) {
                                        Image(systemName: "network")
                                            .font(.system(size: 8))
                                        Text("Port :\(port)")
                                            .font(.system(size: 10).monospaced().bold())
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                                }
                            }

                            HStack(spacing: 12) {
                                if let user = service.user {
                                    Text("User: \(user)").font(.caption).foregroundStyle(.secondary)
                                }
                                if let file = service.file {
                                    Text(file).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        if service.isRunning {
                            HStack(spacing: 16) {
                                if let mem = metric?.formattedMemory {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("RAM").font(.caption2).foregroundStyle(.secondary)
                                        Text(mem).font(.caption.monospaced().bold())
                                    }
                                }
                                if let cpu = metric?.formattedCPU {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("CPU").font(.caption2).foregroundStyle(.secondary)
                                        Text(cpu).font(.caption.monospaced().bold())
                                    }
                                }
                                if let uptime = metric?.formattedUptime {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("Uptime").font(.caption2).foregroundStyle(.secondary)
                                        Text(uptime).font(.caption.monospaced())
                                    }
                                }
                            }
                            .padding(.trailing, 8)
                        }

                        HStack(spacing: 8) {
                            Button {
                                selectedLogService = service
                            } label: {
                                Image(systemName: "text.alignleft")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("View Service Logs")

                            if service.isRunning {
                                Button("Restart") { pendingAction = .single(service: service, action: .restart) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)

                                Button("Stop", role: .destructive) { pendingAction = .single(service: service, action: .stop) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                            } else {
                                Button("Start") { pendingAction = .single(service: service, action: .start) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button {
                        selectedLogService = service
                    } label: {
                        Label("View Logs", systemImage: "text.alignleft")
                    }

                    if let logURL = service.logURL(prefix: manager.brewPrefix),
                       FileManager.default.fileExists(atPath: logURL.path) {
                        Button("Show Log in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        }
                    }

                    if let configURL = service.configURL(prefix: manager.brewPrefix) {
                        Button("Show Config in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([configURL])
                        }
                    }

                    Button("Copy Service Name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.name, forType: .string)
                    }

                    Divider()

                    if service.isRunning {
                        Button("Restart") {
                            pendingAction = .single(service: service, action: .restart)
                        }
                        .disabled(manager.isOperating || !manager.isAvailable)

                        Button("Stop", role: .destructive) {
                            pendingAction = .single(service: service, action: .stop)
                        }
                        .disabled(manager.isOperating || !manager.isAvailable)
                    } else {
                        Button("Start") {
                            pendingAction = .single(service: service, action: .start)
                        }
                        .disabled(manager.isOperating || !manager.isAvailable)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search services")
            .overlay {
                if let error = manager.errorMessage, manager.services.isEmpty, !manager.isLoading {
                    ContentUnavailableView {
                        Label("Services Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry", action: manager.refresh)
                            .buttonStyle(.borderedProminent)
                    }
                } else if manager.services.isEmpty, !manager.isLoading {
                    ContentUnavailableView(
                        "No Services Configured",
                        systemImage: "gearshape.2",
                        description: Text("Install a Homebrew service (e.g. redis, postgresql) to manage it here.")
                    )
                } else if filteredServices.isEmpty, !search.isEmpty {
                    ContentUnavailableView(
                        "No Matching Services",
                        systemImage: "magnifyingglass",
                        description: Text("No services match \"\(search)\".")
                    )
                }
            }
        }
    }

    private var macOSBackgroundItemsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrewStoreSectionSearchBar(
                    text: $backgroundSearch,
                    placeholder: "Search background agents (e.g. Google, Docker, Spotify)…",
                    count: filteredBackgroundItems.count
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if let msg = backgroundManager.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            List(filteredBackgroundItems) { item in
                HStack(spacing: 14) {
                    Circle()
                        .fill(item.isRunning ? Color.green : (item.isLoaded ? Color.blue : Color.secondary.opacity(0.5)))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.displayName)
                                .font(.headline)
                            Text(item.isRunning ? "Running" : (item.isLoaded ? "Loaded" : "Inactive"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (item.isRunning ? Color.green : (item.isLoaded ? Color.blue : Color.secondary))
                                        .opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(item.isRunning ? .green : (item.isLoaded ? .blue : .secondary))

                            if let pid = item.pid, pid > 0 {
                                Text("PID: \(pid)")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            if item.runAtLoad {
                                Text("Runs at boot")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.secondary.opacity(0.08), in: Capsule())
                            }
                        }

                        Text(item.label)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let plistURL = item.plistURL {
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([plistURL])
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if item.isLoaded {
                                Button("Disable") {
                                    backgroundManager.toggleItem(item, enable: false)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button("Enable") {
                                    backgroundManager.toggleItem(item, enable: true)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(role: .destructive) {
                                itemPendingTrash = item
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Move Agent Plist to Trash")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if backgroundManager.isScanning {
                    ProgressView("Scanning background items…")
                } else if backgroundManager.items.isEmpty {
                    ContentUnavailableView(
                        "No Background Items Found",
                        systemImage: "gearshape.2",
                        description: Text("No launch agents or login items were detected.")
                    )
                } else if filteredBackgroundItems.isEmpty, !backgroundSearch.isEmpty {
                    ContentUnavailableView(
                        "No Matching Background Items",
                        systemImage: "magnifyingglass",
                        description: Text("No items match \"\(backgroundSearch)\".")
                    )
                }
            }
        }
    }

    private var confirmationTitle: String {
        guard let action = pendingAction else { return "Confirm Action" }
        switch action {
        case let .single(svc, type):
            switch type {
            case .restart: return "Restart \(svc.name)?"
            case .stop: return "Stop \(svc.name)?"
            case .start: return "Start \(svc.name)?"
            }
        case .batchStart: return "Start All Stopped Daemons?"
        case .batchStop: return "Stop All Running Daemons?"
        case .batchRestart: return "Restart All Active Daemons?"
        case let .autoFixErrored(svcs):
            return svcs.count == 1 ? "Repair Errored Service?" : "Repair \(svcs.count) Errored Services?"
        }
    }

    private var confirmationMessage: String {
        guard let action = pendingAction else { return "" }
        switch action {
        case let .single(svc, type):
            switch type {
            case .restart: return "Gracefully stop \(svc.name) and relaunch it in the background."
            case .stop: return "Background tasks for \(svc.name) will cease until restarted."
            case .start: return "Launch \(svc.name) as a managed background daemon."
            }
        case .batchStart: return "Launch all currently stopped background daemons."
        case .batchStop: return "Stop all running background services managed by Homebrew."
        case .batchRestart: return "Gracefully cycle all running background services to reload configurations."
        case let .autoFixErrored(svcs):
            if svcs.count == 1, let single = svcs.first {
                return "BrewStore will execute 'brew services restart \(single.name)' to recover from its error state."
            }
            return "BrewStore will execute 'brew services restart' for \(svcs.map(\.name).joined(separator: ", ")) to recover from crashed or error states."
        }
    }
}

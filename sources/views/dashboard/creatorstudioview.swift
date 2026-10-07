import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct CreatorStudioView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var accountManager: GitHubAccountManager
    @StateObject private var creatorManager = BrewStoreCreatorRepoManager.shared

    @State private var showingGitHubLogin = false
    @State private var repoForScaffolding: GitHubRepo?
    @State private var copiedRubyCode = false
    @State private var isCalculatingSHA256 = false
    @State private var calculatedSHA256: String?
    @State private var lintStatusMessage: String?
    @State private var isLintPassing: Bool?
    @State private var tapScaffoldMessage: String?
    @State private var repoSearch = ""
    @State private var selectedStudioTab = 0
    var showHeader: Bool = true

    @ViewBuilder
    private var profileOrConnectButton: some View {
        if accountManager.isAuthenticated, let profile = accountManager.profile {
            HStack(spacing: Spacing.sm) {
                if let avatar = profile.avatar_url, let url = URL(string: avatar) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name ?? profile.login).font(.caption.bold())
                    Text("@\(profile.login)").font(.caption2).foregroundStyle(.secondary)
                }

                Button {
                    if let token = UserDefaults.standard.string(forKey: "BrewStore.github.token") {
                        Task {
                            await creatorManager.fetchRepos(token: token)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(creatorManager.isLoading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.sm))
        } else {
            Button {
                showingGitHubLogin = true
            } label: {
                Label("Connect GitHub", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if showHeader {
                    // Header Bar
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "hammer.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                Text("Creator Studio").font(.largeTitle.bold())
                            }
                            Text("Manage your personal Homebrew taps, monitor repositories, and create Formula and Cask recipes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        profileOrConnectButton
                    }
                } else {
                    HStack {
                        Spacer()
                        profileOrConnectButton
                    }
                }

                Picker("", selection: $selectedStudioTab) {
                    Text("My Taps & Repositories").tag(0)
                    Text("Formula & Cask Packaging Suite").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                if selectedStudioTab == 1 {
                    DeveloperPackagingView(manager: manager)
                } else if !accountManager.isAuthenticated {
                    // Logged Out Promo Card
                    loggedOutPromoCard
                } else if creatorManager.isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Discovering your GitHub repositories and Homebrew taps…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(Spacing.xl)
                } else {
                    // Authenticated Content
                    creatorDashboardContent
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .sheet(isPresented: $showingGitHubLogin) {
            GitHubAccountView(accountManager: accountManager, manager: manager)
        }
        .sheet(item: $repoForScaffolding) { repo in
            FormulaScaffolderModal(repo: repo, owner: accountManager.profile?.login ?? "user", manager: manager)
        }
        .onAppear {
            if accountManager.isAuthenticated, creatorManager.repos.isEmpty, !creatorManager.isLoading {
                if let token = UserDefaults.standard.string(forKey: "BrewStore.github.token") {
                    Task {
                        await creatorManager.fetchRepos(token: token)
                    }
                }
            }
        }
    }

    // MARK: - Logged Out Promo Card

    @ViewBuilder
    private var loggedOutPromoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Tools & Tap Management").font(.title3.bold())
                    Text("Connect your GitHub account to synchronize personal Homebrew taps, inspect repositories, and generate Formula and Cask recipes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 20) {
                featureBullet(icon: "square.3.layers.3d.down.forward", title: "Manage Taps", desc: "Auto-detect and tap your personal homebrew repositories.")
                featureBullet(icon: "doc.text.fill", title: "Create Packages", desc: "Turn your release archives into Homebrew recipes.")
                featureBullet(icon: "star.fill", title: "Repository Insights", desc: "View repository stars and local tap installations.")
            }

            HStack {
                Button {
                    showingGitHubLogin = true
                } label: {
                    Label("Connect GitHub Account", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Text("• or use Offline / Local Scaffolder below without GitHub")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

        // Offline / Local Scaffolder & Local Taps Manager
        offlineLocalScaffolderSection
    }

    // MARK: - Offline Local Scaffolder Section

    @State private var localName = ""
    @State private var localDesc = ""
    @State private var localHomepage = ""
    @State private var localUrl = ""
    @State private var localVersion = "1.0.0"
    @State private var localBin = ""
    @State private var localKind: ScaffoldKind = .formula
    @State private var localCopied = false

    private var isRecipeValidForExport: Bool {
        !localName.trimmingCharacters(in: .whitespaces).isEmpty &&
            (localHomepage.hasPrefix("http://") || localHomepage.hasPrefix("https://")) &&
            (localUrl.hasPrefix("http://") || localUrl.hasPrefix("https://")) &&
            !localHomepage.contains("example.com") &&
            !localUrl.contains("example.com") &&
            calculatedSHA256 != nil
    }

    private var generatedLocalRuby: String {
        switch localKind {
        case .formula:
            BrewStoreFormulaScaffolder.scaffoldGenericFormula(
                name: localName,
                desc: localDesc,
                homepage: localHomepage,
                url: localUrl,
                version: localVersion,
                bin: localBin
            )
        case .cask:
            BrewStoreFormulaScaffolder.scaffoldGenericCask(
                name: localName,
                desc: localDesc,
                homepage: localHomepage,
                url: localUrl,
                version: localVersion,
                appName: "\(BrewStoreFormulaScaffolder.rubyClassName(from: localName)).app"
            )
        }
    }

    private var offlineLocalScaffolderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("Offline Formula & Cask Scaffolder (No GitHub Account Needed)", systemImage: "hammer.fill")
                        .font(.headline)
                    Spacer()
                    Picker("Type", selection: $localKind) {
                        ForEach(ScaffoldKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Offline Formula & Cask Scaffolder (No GitHub Account Needed)", systemImage: "hammer.fill")
                        .font(.headline)
                    Picker("Type", selection: $localKind) {
                        ForEach(ScaffoldKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            Text("Generate valid Homebrew Formula and Cask Ruby manifests on your local disk without signing in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Package Name (Required)").font(.caption2.bold())
                    TextField("e.g. mytool", text: $localName).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption2.bold())
                    TextField("e.g. Fast command-line utility", text: $localDesc).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homepage URL (Required)").font(.caption2.bold())
                    TextField("e.g. https://github.com/user/mytool", text: $localHomepage).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Download Archive URL (Required)").font(.caption2.bold())
                        Spacer()
                        if isCalculatingSHA256 {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button("Fetch SHA-256") {
                                guard let url = URL(string: localUrl) else { return }
                                isCalculatingSHA256 = true
                                Task {
                                    if let (data, _) = try? await URLSession.shared.data(from: url) {
                                        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                                        await MainActor.run {
                                            calculatedSHA256 = hash
                                            isCalculatingSHA256 = false
                                        }
                                    } else {
                                        await MainActor.run {
                                            isCalculatingSHA256 = false
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2.bold())
                            .foregroundStyle(.tint)
                        }
                    }
                    TextField("e.g. https://github.com/user/mytool/archive/v1.0.tar.gz", text: $localUrl).textFieldStyle(.roundedBorder)
                }
            }

            if let sha = calculatedSHA256 {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill").foregroundStyle(.green)
                    Text("SHA-256: \(sha)").font(.caption.monospaced()).textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Linter & Action Tools
            HStack(spacing: 10) {
                Button {
                    validateLocalRecipe()
                } label: {
                    Label("Lint Recipe", systemImage: "checkmark.seal.fill")
                }
                .controlSize(.small)

                Button {
                    scaffoldLocalTapFolder()
                } label: {
                    Label("Scaffold Tap Folder…", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
                .disabled(!isRecipeValidForExport)

                Spacer()
            }

            if let msg = lintStatusMessage, let pass = isLintPassing {
                HStack(spacing: 6) {
                    Image(systemName: pass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(pass ? Color.green : Color.orange)
                    Text(msg)
                        .font(.caption.bold())
                        .foregroundStyle(pass ? Color.green : Color.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((pass ? Color.green : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            if let tapMsg = tapScaffoldMessage {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                    Text(tapMsg).font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Generated Ruby Manifest (\(localName.isEmpty ? "formula" : localName).rb)").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(generatedLocalRuby, forType: .string)
                        localCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { localCopied = false }
                    } label: {
                        Label(localCopied ? "Copied!" : "Copy Ruby", systemImage: localCopied ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(!isRecipeValidForExport)

                    Button {
                        let savePanel = NSSavePanel()
                        savePanel.canCreateDirectories = true
                        savePanel.nameFieldStringValue = "\(localName.isEmpty ? "formula" : localName).rb"
                        savePanel.allowedContentTypes = [.init(filenameExtension: "rb") ?? .plainText]
                        if savePanel.runModal() == .OK, let url = savePanel.url {
                            try? generatedLocalRuby.write(to: url, atomically: true, encoding: .utf8)
                        }
                    } label: {
                        Label("Export .rb File…", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    .disabled(!isRecipeValidForExport)
                }

                if isRecipeValidForExport {
                    ScrollView {
                        Text(generatedLocalRuby)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    .frame(maxHeight: 220)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Complete the required fields above to preview your recipe.")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text("Enter a Package Name, Archive URL, and calculate the SHA-256 Checksum, then click 'Lint Recipe'.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func validateLocalRecipe() {
        if localName.trimmingCharacters(in: .whitespaces).isEmpty {
            isLintPassing = false
            lintStatusMessage = "Please enter a package name (cannot be blank)."
            return
        }
        if localDesc.count > 80 {
            isLintPassing = false
            lintStatusMessage = "Description should be 80 characters or fewer (currently \(localDesc.count))."
            return
        }
        if !localHomepage.hasPrefix("http://") && !localHomepage.hasPrefix("https://") {
            isLintPassing = false
            lintStatusMessage = "Please enter a valid homepage URL starting with http:// or https://."
            return
        }
        if !localUrl.hasPrefix("http://") && !localUrl.hasPrefix("https://") {
            isLintPassing = false
            lintStatusMessage = "Please enter a valid download archive URL starting with http:// or https://."
            return
        }
        if localHomepage.contains("example.com") || localUrl.contains("example.com") {
            isLintPassing = false
            lintStatusMessage = "Template placeholder detected: Replace 'example.com' with your project's actual release URL."
            return
        }
        if calculatedSHA256 == nil {
            isLintPassing = false
            lintStatusMessage = "Checksum required: Click 'Fetch SHA-256' or compute your archive's SHA-256 before publishing."
            return
        }
        isLintPassing = true
        lintStatusMessage = "Recipe syntax and release checksum validated successfully."
    }

    private func scaffoldLocalTapFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Choose Tap Root Directory"

        if openPanel.runModal() == .OK, let dirURL = openPanel.url {
            let formulaDir = dirURL.appendingPathComponent("Formula", isDirectory: true)
            let readmeFile = dirURL.appendingPathComponent("README.md")
            try? FileManager.default.createDirectory(at: formulaDir, withIntermediateDirectories: true)
            let formulaFile = formulaDir.appendingPathComponent("\(localName).rb")
            try? generatedLocalRuby.write(to: formulaFile, atomically: true, encoding: .utf8)
            let readmeContent = "# Homebrew Tap\n\nTo install:\n```bash\nbrew tap <user>/<repo>\nbrew install \(localName)\n```\n"
            try? readmeContent.write(to: readmeFile, atomically: true, encoding: .utf8)
            tapScaffoldMessage = "Scaffolded tap structure at: \(dirURL.path)"
        }
    }

    private func featureBullet(icon: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(title).font(.subheadline.bold())
            }
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredCreatorTaps: [GitHubRepo] {
        let q = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return creatorManager.taps }
        return creatorManager.taps.filter {
            $0.name.lowercased().contains(q) || ($0.description?.lowercased().contains(q) == true)
        }
    }

    private var filteredSoftwareRepos: [GitHubRepo] {
        let q = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return creatorManager.softwareRepos }
        return creatorManager.softwareRepos.filter {
            $0.name.lowercased().contains(q) || ($0.description?.lowercased().contains(q) == true)
        }
    }

    // MARK: - Authenticated Dashboard

    @ViewBuilder
    private var creatorDashboardContent: some View {
        if let profile = accountManager.profile {
            VStack(alignment: .leading, spacing: 20) {
                // Overview Summary Stats
                HStack(spacing: 12) {
                    statCard(title: "My Taps", value: "\(creatorManager.taps.count)", icon: "square.3.layers.3d.down.forward", color: .purple)
                    statCard(title: "Software Repos", value: "\(creatorManager.softwareRepos.count)", icon: "shippingbox.fill", color: .blue)
                    statCard(title: "Total GitHub Stars", value: "\(creatorManager.repos.reduce(0) { $0 + $1.stargazers_count })", icon: "star.fill", color: .orange)
                }

                // In-Section Filter
                BrewStoreSectionSearchBar(text: $repoSearch, placeholder: "Search personal taps & software repositories…")

                // Section 1: Creator Taps
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Personal Homebrew Taps (homebrew-*)", systemImage: "square.3.layers.3d.down.forward")
                            .font(.headline)
                        Spacer()
                        Text("\(filteredCreatorTaps.count) detected").font(.caption).foregroundStyle(.secondary)
                    }

                    if filteredCreatorTaps.isEmpty {
                        HStack {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text(repoSearch.isEmpty ? "No repository starting with 'homebrew-' found on your GitHub account. Create a tap repository (e.g. homebrew-tools) on GitHub to get started." : "No personal taps match \"\(repoSearch)\".")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(filteredCreatorTaps) { tapRepo in
                            let isTapped = creatorManager.isTapLocallyInstalled(tapRepo, owner: profile.login, manager: manager)
                            let tapCommand = tapRepo.tapCommandName(owner: profile.login)

                            HStack(spacing: 14) {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(tapCommand).font(.subheadline.bold())
                                        if isTapped {
                                            Text("Tapped Locally")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.green)
                                        } else {
                                            Text("Not Tapped")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(tapRepo.description ?? "Personal Homebrew Tap")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                // Metrics
                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                                        Text("\(tapRepo.stargazers_count)").font(.caption.monospaced())
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "tuningfork").font(.caption2).foregroundStyle(.blue)
                                        Text("\(tapRepo.forks_count)").font(.caption.monospaced())
                                    }
                                }

                                if isTapped {
                                    Button("Un-tap", role: .destructive) {
                                        manager.untap(name: tapCommand)
                                    }
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                } else {
                                    Button("Tap Repo") {
                                        manager.tap(name: tapCommand)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                }

                                if let url = URL(string: tapRepo.html_url) {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Section 2: Creator Software Repos & Scaffolder Studio
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Software Repositories & Formula Scaffolder", systemImage: "hammer.fill")
                            .font(.headline)
                        Spacer()
                        Text("\(filteredSoftwareRepos.count) repositories").font(.caption).foregroundStyle(.secondary)
                    }

                    if filteredSoftwareRepos.isEmpty {
                        HStack {
                            Image(systemName: "shippingbox").foregroundStyle(.secondary)
                            Text(repoSearch.isEmpty ? "No software repositories detected." : "No software repositories match \"\(repoSearch)\".")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(filteredSoftwareRepos.prefix(15)) { repo in
                            HStack(spacing: 14) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(repo.name).font(.subheadline.bold())
                                    Text(repo.description ?? "Software project")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                                        Text("\(repo.stargazers_count)").font(.caption.monospaced())
                                    }
                                }

                                Button {
                                    repoForScaffolding = repo
                                } label: {
                                    Label("Scaffold Formula / Cask", systemImage: "sparkles")
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)

                                if let url = URL(string: repo.html_url) {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Formula / Cask Scaffolding Modal Sheet

struct FormulaScaffolderModal: View {
    @Environment(\.dismiss) private var dismiss
    let repo: GitHubRepo
    let owner: String
    @ObservedObject var manager: HomebrewManager

    @State private var kind: ScaffoldKind = .formula
    @State private var versionInput = "1.0.0"
    @State private var executableName = ""
    @State private var copied = false

    private var generatedRubyCode: String {
        switch kind {
        case .formula:
            BrewStoreFormulaScaffolder.scaffoldFormula(
                repo: repo,
                owner: owner,
                version: versionInput.isEmpty ? "1.0.0" : versionInput,
                binaryName: executableName.isEmpty ? nil : executableName
            )
        case .cask:
            BrewStoreFormulaScaffolder.scaffoldCask(
                repo: repo,
                owner: owner,
                version: versionInput.isEmpty ? "1.0.0" : versionInput,
                appName: executableName.isEmpty ? nil : executableName
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Formula & Cask Scaffolder").font(.title2.bold())
                    Text("Generate a compliant Homebrew recipe for \(repo.full_name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            // Configuration Form
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Picker("Package Type", selection: $kind) {
                        ForEach(ScaffoldKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    TextField("Release Version", text: $versionInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    TextField(kind == .formula ? "Binary Name" : "App Bundle Name", text: $executableName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Package Type", selection: $kind) {
                        ForEach(ScaffoldKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 12) {
                        TextField("Release Version", text: $versionInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)

                        TextField(kind == .formula ? "Binary Name" : "App Bundle Name", text: $executableName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                    }
                }
            }

            // Ruby Preview Editor
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Generated Ruby Recipe (\(kind == .formula ? "\(repo.name).rb" : "\(repo.name.lowercased()).rb") )")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(generatedRubyCode, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy Ruby", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button {
                        exportFormulaFile()
                    } label: {
                        Label("Export File…", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    Text(generatedRubyCode)
                        .font(.system(.body, design: .monospaced))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                .frame(maxHeight: 280)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 480)
    }

    private func exportFormulaFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = kind == .formula ? "\(repo.name).rb" : "\(repo.name.lowercased()).rb"
        savePanel.allowedContentTypes = [.init(filenameExtension: "rb") ?? .plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? generatedRubyCode.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

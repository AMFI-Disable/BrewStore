import AppKit
import SwiftUI

struct ResetViewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    @ObservedObject private var resetManager = BrewStoreResetManager.shared

    @State private var selectedOptions: Set<BrewStoreResetOption> = []
    @State private var showingUninstallSheet = false
    @State private var activeStatusToast: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset BrewStore")
                        .font(.title2.bold())
                    Text("Choose what to reset, from local caches and preferences to package links.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            Divider()

            // Main Scrollable Console
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let message = activeStatusToast ?? resetManager.lastResetMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Tier 1: App Data & Cache
                    categoryCard(
                        tier: .safe,
                        title: "BrewStore Local Data",
                        subtitle: "Clear local cache, wishlists, and unpin version locks.",
                        options: [.unpinEverything, .unstarEverything]
                    )

                    // Tier 2: BrewStore Preferences
                    categoryCard(
                        tier: .caution,
                        title: "App Settings & Preferences",
                        subtitle: "Reset user interface configuration and app preferences.",
                        options: [.clearPersonalSettings, .resetEverythingForApp]
                    )

                    // Tier 3: Homebrew Maintenance & Links
                    categoryCard(
                        tier: .danger,
                        title: "Homebrew Changes & Cleanups",
                        subtitle: "Maintenance and configuration operations affecting your Homebrew environment.",
                        options: [.cleanupEverything, .unlinkEverything, .untapEverything]
                    )

                    // Tier 4: Irreversible Danger Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("UNINSTALL ALL PACKAGES")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                        .padding(.top, 6)

                        Text("Scope: Deletes only software managed by Homebrew. Your personal documents, files, macOS system files, and App Store applications are completely unaffected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        uninstallCategoryCard
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }

            Divider()

            // Footer
            HStack(spacing: Spacing.sm) {
                if !selectedOptions.isEmpty {
                    Text("\(selectedOptions.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Reset Selected (\(selectedOptions.count))") {
                    if selectedOptions.contains(.uninstallEverything) {
                        showingUninstallSheet = true
                    } else {
                        BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: selectedOptions) {
                            resetManager.performSelectiveReset(options: selectedOptions, manager: manager, discovery: discovery)
                            activeStatusToast = resetManager.lastResetMessage
                            selectedOptions.removeAll()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOptions.isEmpty || resetManager.isResetting)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .frame(width: 620, height: 640)
        .sheet(isPresented: $showingUninstallSheet) {
            FullSystemUninstallSheet(manager: manager, resetManager: resetManager)
        }
    }

    // MARK: - Generic Category Card

    private func categoryCard(
        tier: BrewStoreResetTier,
        title: String,
        subtitle: String,
        options: [BrewStoreResetOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: tier.icon)
                    .foregroundStyle(tier.badgeColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(options) { option in
                    HStack(alignment: .top, spacing: 12) {
                        // Checkbox for batch select
                        Button {
                            if selectedOptions.contains(option) {
                                selectedOptions.remove(option)
                            } else {
                                selectedOptions.insert(option)
                            }
                        } label: {
                            Image(systemName: selectedOptions.contains(option) ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(selectedOptions.contains(option) ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                        // Info
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.caption.bold())
                                    .foregroundStyle(tier.badgeColor)
                                Text(option.outcomeTitle)
                                    .font(.subheadline.bold())

                                Text(option.consequenceBadge)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(tier.badgeColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(tier.badgeColor.opacity(0.12), in: Capsule())
                            }

                            Text(option.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        // Direct Action Button
                        Button(option.shortActionTitle) {
                            triggerDirectAction(option)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(
                        Color.secondary.opacity(selectedOptions.contains(option) ? 0.08 : 0.03),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tier.badgeColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Remove All Packages Card

    private var uninstallCategoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Remove All Homebrew Packages")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Text("High Impact")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .cornerRadius(4)
            }

            Text("Uninstalls every Homebrew package and application from your Mac to free up disk space.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                        Text("Remove All Packages")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                    }
                    Text("Completely removes all Homebrew formulae and casks from your Mac. This action cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Remove All Packages…", role: .destructive) {
                    showingUninstallSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Action Execution Router

    private func triggerDirectAction(_ option: BrewStoreResetOption) {
        if option == .uninstallEverything {
            showingUninstallSheet = true
        } else {
            BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [option]) {
                executeSingleAction(option)
            }
        }
    }

    private func executeSingleAction(_ option: BrewStoreResetOption) {
        switch option {
        case .unpinEverything:
            resetManager.unpinEverything(manager: manager)
        case .unstarEverything:
            resetManager.unstarEverything()
        case .cleanupEverything:
            resetManager.cleanupEverything(manager: manager)
        case .clearPersonalSettings:
            resetManager.clearPersonalSettings()
        case .resetEverythingForApp:
            resetManager.resetEverythingForApp(manager: manager, discovery: discovery)
        case .unlinkEverything:
            resetManager.unlinkEverything(manager: manager)
        case .untapEverything:
            resetManager.untapEverything(manager: manager)
        case .uninstallEverything:
            showingUninstallSheet = true
        }
        activeStatusToast = resetManager.lastResetMessage
    }
}

// MARK: - Full System Uninstall Confirmation Sheet

struct FullSystemUninstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var resetManager: BrewStoreResetManager

    @State private var currentStep: Int = 1
    @State private var cooldownSecondsRemaining: Int = 5
    @State private var timerActive: Bool = false
    @State private var typedConfirmationText: String = ""
    @State private var timer: Timer?

    var installedFormulaeCount: Int {
        manager.packages.filter { $0.kind == .formula && $0.isInstalled }.count
    }

    var installedCasksCount: Int {
        manager.packages.filter { $0.kind == .cask && $0.isInstalled }.count
    }

    var isPhraseVerified: Bool {
        resetManager.verifyNuclearPhrase(typedConfirmationText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Remove All Installed Software")
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                        Text("Step \(currentStep) of 3")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }

                    Text("Review affected applications and packages before proceeding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    stopTimer()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            // Step Content
            VStack(alignment: .leading, spacing: 20) {
                if currentStep == 1 {
                    step1SoftwareImpactReview
                } else if currentStep == 2 {
                    step2ConfirmationCooldown
                } else {
                    step3ConfirmationPhrase
                }
            }
            .padding(24)

            Spacer()

            Divider()

            // Navigation Bar
            HStack {
                Button("Cancel") {
                    stopTimer()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if currentStep == 1 {
                    Button("Proceed to Step 2 →") {
                        currentStep = 2
                        startCooldownTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if currentStep == 2 {
                    Button(cooldownSecondsRemaining > 0 ? "Please Review (\(cooldownSecondsRemaining)s)…" : "Proceed to Step 3 →") {
                        stopTimer()
                        currentStep = 3
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(cooldownSecondsRemaining > 0)
                } else {
                    Button("Uninstall All (\(installedFormulaeCount + installedCasksCount)) Packages", role: .destructive) {
                        resetManager.uninstallEverything(manager: manager)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!isPhraseVerified || resetManager.isResetting)
                }
            }
            .padding(16)
        }
        .frame(width: 580, height: 460)
        .onDisappear {
            stopTimer()
        }
    }

    /// Step 1
    private var step1SoftwareImpactReview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 1 of 3: Summary of Affected Software")
                .font(.headline)

            Text("This uninstalls all software installed via Homebrew, including command-line tools, libraries, and GUI applications.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Label("\(installedFormulaeCount) Formulae (CLI Tools & Libraries)", systemImage: "terminal.fill")
                    Spacer()
                    Text("Will be uninstalled")
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Label("\(installedCasksCount) Casks (macOS GUI Applications)", systemImage: "macwindow.on.rectangle")
                    Spacer()
                    Text("Will be uninstalled")
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.callout)
        }
    }

    /// Step 2
    private var step2ConfirmationCooldown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 2 of 3: Important Consequences")
                .font(.headline)

            Text("Please review the consequences before continuing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: CGFloat(cooldownSecondsRemaining) / 5.0)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(cooldownRemaining)")
                        .font(.title2.bold())
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(cooldownSecondsRemaining > 0 ? "Reviewing consequences…" : "Review Complete")
                        .font(.headline)
                    Text("Background services, command-line tools in your PATH, and development packages will be removed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cooldownRemaining: Int {
        cooldownSecondsRemaining
    }

    /// Step 3
    private var step3ConfirmationPhrase: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 3 of 3: Confirm Final Deletion")
                .font(.headline)

            Text("To confirm, type the exact phrase below:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(BrewStoreResetManager.nuclearVerificationPhrase)
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            TextField("Type confirmation phrase here…", text: $typedConfirmationText)
                .textFieldStyle(.roundedBorder)
                .font(.body)

            if !typedConfirmationText.isEmpty, !isPhraseVerified {
                Text("Phrase does not match. Please type exactly 'UNINSTALL ALL PACKAGES'.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isPhraseVerified {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Phrase verified. Action unlocked.")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func startCooldownTimer() {
        cooldownSecondsRemaining = 5
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            Task { @MainActor in
                if self.cooldownSecondsRemaining > 0 {
                    self.cooldownSecondsRemaining -= 1
                } else {
                    t.invalidate()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

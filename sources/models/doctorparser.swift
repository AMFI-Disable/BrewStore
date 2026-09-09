import Foundation

struct BrewStoreDoctorDiagnostic: Identifiable, Hashable, Codable {
    let id: String
    let severity: Severity
    let title: String
    let message: String
    let suggestedCommand: String?
    let isAutoFixable: Bool
    let autoFixCommand: String?
    let requiresSudo: Bool

    enum Severity: String, Codable {
        case warning = "Warning"
        case error = "Error"
        case clean = "Clean"
    }

    init(
        id: String,
        severity: Severity,
        title: String,
        message: String,
        suggestedCommand: String? = nil,
        isAutoFixable: Bool = false,
        autoFixCommand: String? = nil,
        requiresSudo: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.suggestedCommand = suggestedCommand
        self.isAutoFixable = isAutoFixable
        self.autoFixCommand = autoFixCommand
        self.requiresSudo = requiresSudo
    }
}

enum BrewStoreDoctorParser {
    static func parse(_ output: String) -> [BrewStoreDoctorDiagnostic] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("Your system is ready to brew.") {
            return [
                BrewStoreDoctorDiagnostic(
                    id: "clean",
                    severity: .clean,
                    title: "System Ready",
                    message: "Your system is ready to brew. No issues were found.",
                    suggestedCommand: nil,
                    isAutoFixable: false,
                    autoFixCommand: nil,
                    requiresSudo: false
                )
            ]
        }

        var diagnostics: [BrewStoreDoctorDiagnostic] = []
        let rawChunks = trimmed.components(separatedBy: "\n\n")

        for (index, chunk) in rawChunks.enumerated() {
            let lines = chunk.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            var title = lines[0]
            var severity: BrewStoreDoctorDiagnostic.Severity = .warning

            if title.hasPrefix("Warning:") {
                title = String(title.dropFirst("Warning:".count)).trimmingCharacters(in: .whitespaces)
            } else if title.hasPrefix("Error:") {
                title = String(title.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
                severity = .error
            }

            let message = lines.dropFirst().joined(separator: "\n")
            var suggestedCommand: String?

            for line in lines {
                if line.hasPrefix("brew ") || line.hasPrefix("sudo ") || line.hasPrefix("export ") || line.hasPrefix("xcode-select ") || line.hasPrefix("rm ") || line.hasPrefix("chown ") {
                    suggestedCommand = line
                    break
                }
            }

            var isAutoFixable = false
            var autoFixCommand: String?
            var requiresSudo = false

            if let cmd = suggestedCommand {
                if cmd.hasPrefix("brew link ") || cmd.hasPrefix("brew tap ") || cmd.hasPrefix("brew cleanup") || cmd.hasPrefix("brew update") {
                    isAutoFixable = true
                    autoFixCommand = cmd
                    requiresSudo = false
                } else if cmd.hasPrefix("sudo ") {
                    requiresSudo = true
                }
            }

            diagnostics.append(
                BrewStoreDoctorDiagnostic(
                    id: "diag-\(index)",
                    severity: severity,
                    title: title.isEmpty ? "Configuration Notice" : title,
                    message: message.isEmpty ? title : message,
                    suggestedCommand: suggestedCommand,
                    isAutoFixable: isAutoFixable,
                    autoFixCommand: autoFixCommand,
                    requiresSudo: requiresSudo
                )
            )
        }

        return diagnostics
    }
}

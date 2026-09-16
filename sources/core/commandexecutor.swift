import Darwin
import Foundation

enum BrewStoreCommandCategory: String, Codable, Equatable, Sendable {
    case readOnly
    case reversibleMutation
    case destructiveMutation
    case privilegedOrUnsupported
}

struct BrewStoreCommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32?
    let wasTerminated: Bool
    let didTimeOut: Bool
    let wasCancelled: Bool
    let standardOutputWasTruncated: Bool
    let standardErrorWasTruncated: Bool
    let category: BrewStoreCommandCategory
    let launchErrorDescription: String?

    var succeeded: Bool {
        !didTimeOut && !wasCancelled && !wasTerminated && launchErrorDescription == nil && terminationStatus == 0
    }
}

final class BrewStoreCommandExecutor: @unchecked Sendable {
    static let shared = BrewStoreCommandExecutor()

    typealias CustomHandler = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ timeout: TimeInterval,
        _ category: BrewStoreCommandCategory,
        _ maximumOutputBytes: Int,
        _ cancellationCheck: (@Sendable () -> Bool)?,
        _ onOutput: (@Sendable (String) -> Void)?
    ) -> BrewStoreCommandResult?

    private let customHandler: CustomHandler?
    var hasCustomHandler: Bool {
        customHandler != nil
    }

    init(customHandler: CustomHandler? = nil) {
        self.customHandler = customHandler
    }

    func run(
        executablePath: String,
        arguments: [String] = [],
        timeout: TimeInterval = 30,
        category: BrewStoreCommandCategory = .readOnly,
        maximumOutputBytes: Int = 1_048_576,
        cancellationCheck: (@Sendable () -> Bool)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> BrewStoreCommandResult {
        if let custom = customHandler?(executablePath, arguments, timeout, category, maximumOutputBytes, cancellationCheck, onOutput) {
            return custom
        }
        if BrewStoreFixtureMode.isEnabled, let fixtureResult = BrewStoreFixtureMode.fixtureCommandHandler(executablePath, arguments, timeout, category, maximumOutputBytes, cancellationCheck, onOutput) {
            return fixtureResult
        }

        guard executablePath.hasPrefix("/") else {
            return failure("The executable path must be absolute.", category: category)
        }
        guard ExecutionSecurityBoundary.isExecutableAllowed(executablePath: executablePath) else {
            return failure("The executable path '\(executablePath)' is not permitted by BrewStore security boundaries.", category: category)
        }
        guard maximumOutputBytes > 0 else {
            return failure("The output limit must be greater than zero.", category: category)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = ExecutionSecurityBoundary.sanitizeEnvironment(ProcessInfo.processInfo.environment)
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            try? inputPipe.fileHandleForWriting.close()
            return BrewStoreCommandResult(
                standardOutput: "", standardError: "", terminationStatus: nil,
                wasTerminated: false, didTimeOut: false, wasCancelled: false,
                standardOutputWasTruncated: false, standardErrorWasTruncated: false,
                category: category, launchErrorDescription: error.localizedDescription
            )
        }

        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        let group = DispatchGroup()
        let output = BrewStoreOutputBuffer(onOutput: onOutput)
        let error = BrewStoreOutputBuffer(onOutput: onOutput)

        group.enter()
        let outputThread = Thread {
            output.capture(from: outputPipe, maximumBytes: maximumOutputBytes)
            group.leave()
        }
        outputThread.name = "BrewStore.CommandExecutor.Output"
        outputThread.qualityOfService = .userInitiated
        outputThread.start()

        group.enter()
        let errorThread = Thread {
            error.capture(from: errorPipe, maximumBytes: maximumOutputBytes)
            group.leave()
        }
        errorThread.name = "BrewStore.CommandExecutor.Error"
        errorThread.qualityOfService = .userInitiated
        errorThread.start()
        let deadline = Date().addingTimeInterval(timeout.isFinite ? max(timeout, 0) : 30)
        var wasCancelled = cancellationCheck?() == true

        if wasCancelled {
            process.terminate()
        } else {
            let waitStep: DispatchTimeInterval = .milliseconds(25)
            while process.isRunning, Date() < deadline {
                if cancellationCheck?() == true {
                    wasCancelled = true
                    process.terminate()
                    break
                }
                if exitSemaphore.wait(timeout: .now() + waitStep) == .success {
                    break
                }
                if group.wait(timeout: .now()) == .success {
                    break
                }
            }
        }

        // Safely reap process if it has completed normally
        if !wasCancelled && !process.isRunning {
            process.waitUntilExit()
        }

        let didTimeOut = process.isRunning && !wasCancelled && Date() >= deadline
        if wasCancelled || didTimeOut {
            if process.isRunning {
                process.terminate()
                let gracefulDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning, Date() < gracefulDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning {
                    let pid = process.processIdentifier
                    if pid > 1, pid != getpid() {
                        let pgid = getpgid(pid)
                        if pgid > 1, pgid != getpgrp() {
                            kill(-pgid, SIGKILL)
                        }
                        kill(pid, SIGKILL)
                    }
                    let killDeadline = Date().addingTimeInterval(0.2)
                    while process.isRunning, Date() < killDeadline {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                }
            }
        }

        // Safely wait for process exit without indefinite hang
        if process.isRunning {
            let hardExitDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < hardExitDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        if !process.isRunning || group.wait(timeout: .now()) == .success {
            process.waitUntilExit()
        }

        // Wait for output capture threads to finish reading EOF before closing handles
        if group.wait(timeout: .now() + 1.0) == .timedOut {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            _ = group.wait(timeout: .now() + 0.2)
        } else {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        let isStillRunning = process.isRunning
        let exitCode: Int32? = isStillRunning ? nil : process.terminationStatus
        let wasTerminatedBySignal = !isStillRunning && (process.terminationReason == .uncaughtSignal)
        let outputSnapshot = output.snapshot()
        let errorSnapshot = error.snapshot()

        let rawStdOut = String(data: outputSnapshot.data, encoding: .utf8) ?? ""
        let rawStdErr = String(data: errorSnapshot.data, encoding: .utf8) ?? ""

        return BrewStoreCommandResult(
            standardOutput: rawStdOut.strippingANSIEscapeCodes(),
            standardError: rawStdErr.strippingANSIEscapeCodes(),
            terminationStatus: exitCode,
            wasTerminated: didTimeOut || wasCancelled || wasTerminatedBySignal,
            didTimeOut: didTimeOut,
            wasCancelled: wasCancelled,
            standardOutputWasTruncated: outputSnapshot.truncated,
            standardErrorWasTruncated: errorSnapshot.truncated,
            category: category,
            launchErrorDescription: nil
        )
    }

    private func failure(_ message: String, category: BrewStoreCommandCategory) -> BrewStoreCommandResult {
        BrewStoreCommandResult(
            standardOutput: "", standardError: "", terminationStatus: nil,
            wasTerminated: false, didTimeOut: false, wasCancelled: false,
            standardOutputWasTruncated: false, standardErrorWasTruncated: false,
            category: category, launchErrorDescription: message
        )
    }
}

private final class BrewStoreOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private let onOutput: (@Sendable (String) -> Void)?

    init(onOutput: (@Sendable (String) -> Void)? = nil) {
        self.onOutput = onOutput
    }

    func capture(from pipe: Pipe, maximumBytes: Int) {
        var captured = Data()
        var didTruncate = false
        while true {
            // Using safe Swift read(upToCount:) instead of ObjC readData to avoid NSFileHandleOperationException crashes
            guard let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                break
            }
            let remaining = maximumBytes - captured.count
            if remaining > 0 {
                captured.append(chunk.prefix(remaining))
            }
            if chunk.count > max(remaining, 0) {
                didTruncate = true
            }
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                onOutput?(str.strippingANSIEscapeCodes())
            }
        }
        lock.lock()
        data = captured
        truncated = didTruncate
        lock.unlock()
    }

    func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}

private extension String {
    func strippingANSIEscapeCodes() -> String {
        guard self.contains("\u{001B}") else { return self }
        return self.replacingOccurrences(
            of: #"\x1B\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        )
    }
}

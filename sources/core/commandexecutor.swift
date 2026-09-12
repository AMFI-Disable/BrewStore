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
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return BrewStoreCommandResult(
                standardOutput: "", standardError: "", terminationStatus: nil,
                wasTerminated: false, didTimeOut: false, wasCancelled: false,
                standardOutputWasTruncated: false, standardErrorWasTruncated: false,
                category: category, launchErrorDescription: error.localizedDescription
            )
        }

        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }

        let group = DispatchGroup()
        let output = BrewStoreOutputBuffer(onOutput: onOutput)
        let error = BrewStoreOutputBuffer(onOutput: onOutput)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output.capture(from: outputPipe, maximumBytes: maximumOutputBytes)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            error.capture(from: errorPipe, maximumBytes: maximumOutputBytes)
            group.leave()
        }
        let deadline = Date().addingTimeInterval(timeout.isFinite ? max(timeout, 0) : 30)
        var wasCancelled = cancellationCheck?() == true

        if wasCancelled {
            process.terminate()
        } else {
            let waitStep: DispatchTimeInterval = cancellationCheck != nil ? .milliseconds(20) : .milliseconds(min(Int(max(timeout, 0.05) * 1000), 30_000))
            while process.isRunning && Date() < deadline {
                if cancellationCheck?() == true {
                    wasCancelled = true
                    process.terminate()
                    break
                }
                if exitSemaphore.wait(timeout: .now() + waitStep) == .success {
                    break
                }
            }
        }

        let didTimeOut = process.isRunning && !wasCancelled && Date() >= deadline
        if process.isRunning {
            process.terminate()
            let gracefulDeadline = Date().addingTimeInterval(0.2)
            while process.isRunning, Date() < gracefulDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                let pid = process.processIdentifier
                if pid > 1, pid != getpid() {
                    kill(pid, SIGKILL)
                }
                let killDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning, Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
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
        if !process.isRunning {
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

        return BrewStoreCommandResult(
            standardOutput: String(data: outputSnapshot.data, encoding: .utf8) ?? "",
            standardError: String(data: errorSnapshot.data, encoding: .utf8) ?? "",
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
                onOutput?(str)
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

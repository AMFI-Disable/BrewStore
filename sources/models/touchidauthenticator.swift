import Foundation
import LocalAuthentication

@MainActor
final class BrewStoreTouchIDAuthenticator: ObservableObject {
    static let shared = BrewStoreTouchIDAuthenticator()

    @Published var isBiometricsAvailable: Bool = false
    @Published var biometryTypeDescription: String = "Touch ID / Password"

    init() {
        checkBiometricsAvailability()
    }

    func checkBiometricsAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isBiometricsAvailable = canEvaluate

        if canEvaluate {
            biometryTypeDescription = "Touch ID"
        } else {
            biometryTypeDescription = "System Password"
        }
    }

    func authenticate(reason: String = "Authorize Homebrew administrative installation") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            return false
        }
    }
}

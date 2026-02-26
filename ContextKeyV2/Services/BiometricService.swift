import Foundation
import LocalAuthentication

// MARK: - Biometric Service

/// Handles FaceID/TouchID authentication
@MainActor
final class BiometricService: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isLocked = true
    @Published var errorMessage: String?

    enum BiometricType {
        case faceID
        case touchID
        case passcode
        case none
    }

    var availableBiometric: BiometricType {
        let context = LAContext()  // Fresh context each time — avoids stale state
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Check if at least passcode is available
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return .passcode
            }
            return .none
        }

        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }

    /// Authenticate the user — gates app access and copy actions
    func authenticate(reason: String = "Unlock your context") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // Try biometrics first, fall back to passcode
        let policy: LAPolicy = .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            isAuthenticated = success
            isLocked = !success
            errorMessage = nil
            return success
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            // User or system cancelled — don't show an error message
            isAuthenticated = false
            isLocked = true
            return false
        } catch {
            isAuthenticated = false
            isLocked = true
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Unlock without triggering biometric auth (e.g., after onboarding)
    func unlockWithoutAuth() {
        isAuthenticated = true
        isLocked = false
        errorMessage = nil
    }

    /// Lock the app (e.g., when going to background)
    func lock() {
        isAuthenticated = false
        isLocked = true
    }
}

import Foundation
import LocalAuthentication

struct BiometricAuthService {
    func authenticate(reason: String, allowsDevicePasscode: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            let policy: LAPolicy = allowsDevicePasscode
                ? .deviceOwnerAuthentication
                : .deviceOwnerAuthenticationWithBiometrics
            guard context.canEvaluatePolicy(policy, error: &error) else {
                continuation.resume(returning: false)
                return
            }
            if !allowsDevicePasscode, context.biometryType != .faceID {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

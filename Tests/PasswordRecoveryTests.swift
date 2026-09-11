import Foundation
import Security

@main
enum PasswordRecoveryTests {
    static func main() {
        passwordVerificationDistinguishesEveryStorageOutcome()
        failedUpdatePreservesExistingPassword()
        missingPasswordUsesAddWithoutDelete()
        duplicateAddRetriesAtomicUpdate()
        onlyMismatchRequestsFailureRecording()
        passwordSetupRejectsSurroundingWhitespace()
        recoveryRequiresPrimaryTrustedDisplayWhenProtectionIsEnabled()
        recoveryAuthorizationExpiresAndIsOneAtATime()
        print("Password recovery tests passed")
    }

    private static func passwordVerificationDistinguishesEveryStorageOutcome() {
        let keychain = FakeKeychain()
        let manager = KeychainManager(keychain: keychain)

        keychain.storedData = Data("correct horse".utf8)
        precondition(manager.verifyPassword("correct horse") == .match)
        precondition(manager.verifyPassword("different") == .mismatch)

        keychain.storedData = nil
        precondition(manager.verifyPassword("anything") == .notFound)

        keychain.copyStatus = errSecAuthFailed
        precondition(manager.verifyPassword("anything") == .accessFailure(errSecAuthFailed))

        keychain.copyStatus = errSecSuccess
        keychain.storedData = Data([0xFF])
        precondition(manager.verifyPassword("anything") == .decodeFailure)
    }

    private static func failedUpdatePreservesExistingPassword() {
        let keychain = FakeKeychain()
        keychain.storedData = Data("existing password".utf8)
        keychain.updateStatus = errSecAuthFailed
        let manager = KeychainManager(keychain: keychain)

        precondition(manager.savePassword("replacement password") == .accessFailure(errSecAuthFailed))
        precondition(keychain.storedData == Data("existing password".utf8))
        precondition(keychain.addCallCount == 0)
        precondition(keychain.deleteCallCount == 0)
    }

    private static func missingPasswordUsesAddWithoutDelete() {
        let keychain = FakeKeychain()
        let manager = KeychainManager(keychain: keychain)

        precondition(manager.savePassword("new password") == .saved)
        precondition(keychain.storedData == Data("new password".utf8))
        precondition(keychain.updateCallCount == 1)
        precondition(keychain.addCallCount == 1)
        precondition(keychain.deleteCallCount == 0)
    }

    private static func duplicateAddRetriesAtomicUpdate() {
        let keychain = FakeKeychain()
        keychain.addStatus = errSecDuplicateItem
        keychain.onAdd = {
            keychain.storedData = Data("racing writer".utf8)
            keychain.updateStatus = nil
        }
        let manager = KeychainManager(keychain: keychain)

        precondition(manager.savePassword("replacement password") == .saved)
        precondition(keychain.storedData == Data("replacement password".utf8))
        precondition(keychain.updateCallCount == 2)
        precondition(keychain.addCallCount == 1)
    }

    private static func onlyMismatchRequestsFailureRecording() {
        precondition(PasswordAuthenticationPolicy.resolve(verification: .match) == .authenticated)
        precondition(PasswordAuthenticationPolicy.resolve(verification: .mismatch) == .recordMismatch)
        precondition(PasswordAuthenticationPolicy.resolve(verification: .notFound) == .failure(.noPasswordSet))
        precondition(
            PasswordAuthenticationPolicy.resolve(verification: .accessFailure(errSecAuthFailed))
                == .failure(.passwordStorageUnavailable)
        )
        precondition(
            PasswordAuthenticationPolicy.resolve(verification: .decodeFailure)
                == .failure(.passwordDataInvalid)
        )
    }

    private static func passwordSetupRejectsSurroundingWhitespace() {
        precondition(PasswordSetupPolicy.validate(password: "abcd", confirmation: "abcd") == .valid)
        precondition(
            PasswordSetupPolicy.validate(password: " abcd", confirmation: " abcd")
                == .surroundingWhitespace
        )
        precondition(
            PasswordSetupPolicy.validate(password: "abcd ", confirmation: "abcd ")
                == .surroundingWhitespace
        )
        precondition(
            PasswordSetupPolicy.validate(password: "abcd", confirmation: "abce") == .mismatch
        )
    }

    private static func recoveryRequiresPrimaryTrustedDisplayWhenProtectionIsEnabled() {
        let trusted = DisplayConfigurationStatus(
            currentFingerprints: ["primary"],
            trustedFingerprints: ["primary"]
        )
        let untrusted = DisplayConfigurationStatus(
            currentFingerprints: ["primary", "unknown"],
            trustedFingerprints: ["primary"]
        )

        precondition(PasswordRecoveryPolicy.isEligible(
            isPrimaryDisplay: true,
            displayProtectionEnabled: true,
            displayStatus: trusted
        ))
        precondition(!PasswordRecoveryPolicy.isEligible(
            isPrimaryDisplay: false,
            displayProtectionEnabled: true,
            displayStatus: trusted
        ))
        precondition(!PasswordRecoveryPolicy.isEligible(
            isPrimaryDisplay: true,
            displayProtectionEnabled: true,
            displayStatus: untrusted
        ))
        precondition(PasswordRecoveryPolicy.isEligible(
            isPrimaryDisplay: true,
            displayProtectionEnabled: false,
            displayStatus: untrusted
        ))
    }

    private static func recoveryAuthorizationExpiresAndIsOneAtATime() {
        var state = PasswordRecoveryAuthorizationState()
        let first = state.issue(now: 100, lifetime: 120)
        precondition(state.isValid(first, now: 220))

        let second = state.issue(now: 300, lifetime: 120)
        precondition(!state.isValid(first, now: 301))
        precondition(state.isValid(second, now: 301))
        precondition(!state.isValid(second, now: 421))
    }
}

private final class FakeKeychain: KeychainAccessing {
    var storedData: Data?
    var copyStatus: OSStatus?
    var updateStatus: OSStatus?
    var addStatus: OSStatus?
    var onAdd: (() -> Void)?
    private(set) var updateCallCount = 0
    private(set) var addCallCount = 0
    private(set) var deleteCallCount = 0

    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus {
        if let copyStatus {
            return copyStatus
        }
        guard let storedData else { return errSecItemNotFound }
        result?.pointee = storedData as CFData
        return errSecSuccess
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        updateCallCount += 1
        if let updateStatus {
            return updateStatus
        }
        guard storedData != nil else { return errSecItemNotFound }
        guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
            return errSecParam
        }
        storedData = data
        return errSecSuccess
    }

    func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        addCallCount += 1
        onAdd?()
        if let addStatus {
            return addStatus
        }
        guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
            return errSecParam
        }
        storedData = data
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        deleteCallCount += 1
        storedData = nil
        return errSecSuccess
    }
}

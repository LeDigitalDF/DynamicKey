// ExtensionVerifyApprovalStore.swift
// Short-lived in-memory approvals after successful extension verify (M5).
//
// Flow: verify grants access → fill-approve checks matching request id within TTL.

import Foundation

struct ExtensionVerifyApproval: Equatable {
    let verificationRequestId: String
    let origin: String
    let expiresAt: Date
}

final class ExtensionVerifyApprovalStore {
    static let shared = ExtensionVerifyApprovalStore()

    private var approvals: [String: ExtensionVerifyApproval] = [:]
    private let lock = NSLock()

    private init() {}

    /// Records a successful verify so fill-approve can reference it shortly after.
    func store(granted: Bool, verificationRequestId: String, origin: String, now: Date = Date()) {
        guard granted else { return }
        let approval = ExtensionVerifyApproval(
            verificationRequestId: verificationRequestId,
            origin: SiteCredential.storageKey(for: origin),
            expiresAt: now.addingTimeInterval(ExtensionAuthConfig.fillApprovalLifetimeSeconds)
        )
        lock.lock()
        approvals[verificationRequestId] = approval
        lock.unlock()
    }

    /// Returns a still-valid approval when origin and request id match.
    func approval(
        verificationRequestId: String,
        origin: String,
        now: Date = Date()
    ) -> ExtensionVerifyApproval? {
        lock.lock()
        defer { lock.unlock() }
        pruneExpired(now: now)
        guard let approval = approvals[verificationRequestId],
              SiteCredential.sameSiteGroup(approval.origin, origin),
              approval.expiresAt > now else {
            return nil
        }
        return approval
    }

    private func pruneExpired(now: Date) {
        approvals = approvals.filter { $0.value.expiresAt > now }
    }
}

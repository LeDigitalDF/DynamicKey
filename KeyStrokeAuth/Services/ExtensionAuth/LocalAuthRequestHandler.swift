// LocalAuthRequestHandler.swift
// Routes extension HTTP requests to profile verification and pairing (M5).
//
// Flow: parse JSON → auth check (except status/pair) → call ProfileStore → JSON response.

import AppKit
import Foundation

final class LocalAuthRequestHandler {
    private let profileStore = ProfileStore.shared
    private let pairingStore = ExtensionPairingStore.shared
    private let approvalStore = ExtensionVerifyApprovalStore.shared
    private let credentialStore = CredentialStore.shared
    private let credentialProvisioner = SiteCredentialProvisioner.shared
    private let sitePolicyStore = SitePolicyStore.shared
    private let dynamicShieldPolicyStore = DynamicShieldPolicyStore.shared
    private let auditLog = AuditLogService.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let startedAt = Date()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Dispatches an HTTP request to the correct protocol handler.
    func handle(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        switch (request.method.uppercased(), request.path) {
        case ("GET", ExtensionAuthConfig.Route.status):
            return handleStatus()
        case ("POST", ExtensionAuthConfig.Route.pair):
            return handlePair(request)
        case ("POST", ExtensionAuthConfig.Route.verify):
            return handleVerify(request)
        case ("POST", ExtensionAuthConfig.Route.fillApprove):
            return handleFillApprove(request)
        case ("POST", ExtensionAuthConfig.Route.resetLockout):
            return handleResetLockout(request)
        case ("POST", ExtensionAuthConfig.Route.allowlistCheck):
            return handleAllowlistCheck(request)
        case ("POST", ExtensionAuthConfig.Route.allowlistAdd):
            return handleAllowlistAdd(request)
        case ("POST", ExtensionAuthConfig.Route.allowlistIgnore):
            return handleAllowlistIgnore(request)
        case ("POST", ExtensionAuthConfig.Route.dynamicShieldTrust):
            return handleDynamicShieldTrust(request)
        case ("POST", ExtensionAuthConfig.Route.dynamicShieldList):
            return handleDynamicShieldList(request)
        case ("POST", ExtensionAuthConfig.Route.dynamicShieldEvent):
            return handleDynamicShieldEvent(request)
        case ("POST", ExtensionAuthConfig.Route.credentialsCheck):
            return handleCredentialCheck(request)
        case ("POST", ExtensionAuthConfig.Route.openApp):
            return handleOpenApp(request)
        case ("POST", ExtensionAuthConfig.Route.safeModeActivate):
            return handleSafeModeActivate(request)
        case ("POST", ExtensionAuthConfig.Route.safeModeDeactivate):
            return handleSafeModeDeactivate(request)
        case ("OPTIONS", _):
            return preflightResponse()
        default:
            return LocalHTTPParser.errorResponse(
                statusCode: 404,
                statusText: "Not Found",
                error: "not_found",
                message: "Unknown route \(request.method) \(request.path)"
            )
        }
    }

    // MARK: - Handlers

    /// Returns service health without authentication.
    private func handleStatus() -> LocalHTTPResponse {
        let lockout = profileStore.lockoutStatus()
        let lockoutActive: Bool
        if case .locked = lockout {
            lockoutActive = true
        } else {
            lockoutActive = false
        }

        let uptime = max(0, Int(Date().timeIntervalSince(startedAt)))
        let lastVerifiedAt = HomeDashboardModel.lastLoginDate(from: auditLog.events())
        let safeMode = safeModeStatusOnMain()
        let body = ExtensionStatusResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            serviceState: "running",
            hasProfile: profileStore.hasProfile,
            passThreshold: RhythmSettings.passThreshold,
            pairedClientCount: PairedBrowserDisplay.normalizedClients(pairingStore.pairedClients()).count,
            lockoutActive: lockoutActive,
            serviceUptimeSeconds: uptime,
            lastVerifiedAt: lastVerifiedAt,
            dynamicShieldTrustedRevision: dynamicShieldPolicyStore.trustedPolicyRevision(),
            safeModeActive: safeMode.active,
            safeModeExpiresAt: safeMode.expiresAt,
            safeModeRemainingLabel: safeMode.formattedRemainingTime
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: body, encoder: encoder)
    }

    /// Exchanges a one-time pairing code for a bearer access token.
    private func handlePair(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let pairRequest = decode(ExtensionPairRequest.self, from: request.body) else {
            return badRequest("Invalid pair request JSON.")
        }

        guard pairRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        do {
            let client = try pairingStore.pairClient(
                pairingCode: pairRequest.pairingCode,
                clientName: pairRequest.clientName,
                browserFamily: pairRequest.browserFamily
            )
            auditLog.append(
                AuditEvent(
                    type: .extensionPaired,
                    detail: "\(client.clientName ?? client.id) (\(client.browserFamily ?? "unknown"))"
                )
            )
            let response = ExtensionPairResponse(
                protocolVersion: ExtensionAuthConfig.protocolVersion,
                accessToken: client.accessToken,
                clientId: client.id,
                clientName: client.clientName
            )
            Task { @MainActor in
                LocalAuthServiceManager.shared.refreshPairedClients()
                LocalAuthServiceManager.shared.refreshPairingCodeState()
            }
            return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
        } catch {
            return LocalHTTPParser.errorResponse(
                statusCode: 401,
                statusText: "Unauthorized",
                error: "pairing_failed",
                message: error.localizedDescription
            )
        }
    }

    /// Verifies password and rhythm for a website origin from extension timing data.
    private func handleVerify(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let verifyRequest = decode(ExtensionVerifyRequest.self, from: request.body) else {
            return badRequest("Invalid verify request JSON.")
        }

        guard verifyRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard !verifyRequest.origin.isEmpty else {
            return badRequest("Origin is required.")
        }

        guard sitePolicyStore.isOriginAllowed(verifyRequest.origin) else {
            return LocalHTTPParser.errorResponse(
                statusCode: 403,
                statusText: "Forbidden",
                error: "origin_not_allowed",
                message: "This website is not on your Protected Websites list."
            )
        }

        let trustEvaluation: TrustContextEvaluation = {
            if Thread.isMainThread {
                return TrustContextStore.shared.evaluateForUnlock()
            }
            return DispatchQueue.main.sync {
                TrustContextStore.shared.evaluateForUnlock()
            }
        }()
        guard trustEvaluation.allowed else {
            if trustEvaluation.denialReason == .untrustedKeyboard {
                auditLog.append(AuditEvent(type: .loginFailedUntrustedKeyboard, detail: verifyRequest.origin))
            } else if trustEvaluation.denialReason == .untrustedNetwork {
                auditLog.append(AuditEvent(type: .loginFailedUntrustedNetwork, detail: verifyRequest.origin))
            }
            let denied = LoginVerificationResult(
                granted: false,
                matchPercentage: 0,
                denialReason: trustEvaluation.denialReason
            )
            approvalStore.store(
                granted: false,
                verificationRequestId: verifyRequest.requestId,
                origin: verifyRequest.origin
            )
            auditLog.append(
                AuditEvent(
                    type: .extensionVerifyDenied,
                    detail: "\(verifyRequest.origin) — context trust"
                )
            )
            let response = ExtensionVerifyResponse.from(
                requestId: verifyRequest.requestId,
                result: denied
            )
            return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
        }

        let result = profileStore.verifyLogin(
            password: verifyRequest.password,
            loginData: verifyRequest.keystrokes,
            enforceSecurity: true
        )

        approvalStore.store(
            granted: result.granted,
            verificationRequestId: verifyRequest.requestId,
            origin: verifyRequest.origin
        )

        if result.granted {
            let intent = SiteFormIntent.from(verifyRequest.formIntent)
            var credentialCreated: Bool?
            var siteCredentialReady: Bool?
            var missingSiteCredential: Bool?
            var provisionNote: String?

            do {
                if let provision = try credentialProvisioner.prepareCredential(
                    forOrigin: verifyRequest.origin,
                    username: verifyRequest.username,
                    intent: intent
                ) {
                    siteCredentialReady = true
                    credentialCreated = provision.created
                    if provision.created {
                        auditLog.append(
                            AuditEvent(
                                type: .siteCredentialGenerated,
                                detail: "\(verifyRequest.origin) — \(intent.rawValue)"
                            )
                        )
                    }
                } else if intent == .login {
                    siteCredentialReady = false
                    missingSiteCredential = true
                } else if intent == .changePassword {
                    siteCredentialReady = false
                    missingSiteCredential = true
                }
            } catch {
                provisionNote = "credential save failed: \(error.localizedDescription)"
            }

            var successDetail = "\(verifyRequest.origin) — \(result.matchPercentage)% — \(intent.rawValue)"
            if let provisionNote {
                successDetail += " — \(provisionNote)"
            }
            auditLog.append(
                AuditEvent(
                    type: .extensionVerifySuccess,
                    detail: successDetail
                )
            )

            let response = ExtensionVerifyResponse.from(
                requestId: verifyRequest.requestId,
                result: result,
                siteCredentialReady: siteCredentialReady,
                credentialCreated: credentialCreated,
                missingSiteCredential: missingSiteCredential
            )
            return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
        } else {
            auditLog.append(
                AuditEvent(
                    type: .extensionVerifyDenied,
                    detail: "\(verifyRequest.origin) — \(result.matchPercentage)%"
                )
            )
        }

        let response = ExtensionVerifyResponse.from(
            requestId: verifyRequest.requestId,
            result: result
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Approves autofill only when a recent successful verify exists for the same origin.
    private func handleFillApprove(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let fillRequest = decode(ExtensionFillApproveRequest.self, from: request.body) else {
            return badRequest("Invalid fill-approve request JSON.")
        }

        guard fillRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard sitePolicyStore.isOriginAllowed(fillRequest.origin) else {
            let response = ExtensionFillApproveResponse(
                protocolVersion: ExtensionAuthConfig.protocolVersion,
                requestId: fillRequest.requestId,
                approved: false,
                expiresAt: nil,
                message: "This website is not on your Protected Websites list.",
                credentials: nil
            )
            return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
        }

        if let approval = approvalStore.approval(
            verificationRequestId: fillRequest.verificationRequestId,
            origin: fillRequest.origin
        ) {
            auditLog.append(
                AuditEvent(
                    type: .extensionFillApproved,
                    detail: fillRequest.origin
                )
            )

            let intent = SiteFormIntent.from(fillRequest.formIntent)
            var fillCredentials: ExtensionFillCredentials?
            var missingMessage: String?

            if intent == .changePassword, fillRequest.rotateSitePassword == true {
                let previousPassword = credentialProvisioner.storedPassword(forOrigin: fillRequest.origin)
                do {
                    if let provision = try credentialProvisioner.regenerateForPasswordChangeAtFill(
                        forOrigin: fillRequest.origin,
                        username: fillRequest.username
                    ) {
                        auditLog.append(
                            AuditEvent(
                                type: .siteCredentialGenerated,
                                detail: "\(fillRequest.origin) — changePassword"
                            )
                        )
                        fillCredentials = ExtensionFillCredentials(
                            username: provision.credential.username,
                            password: provision.credential.password,
                            currentPassword: previousPassword
                        )
                    } else {
                        missingMessage = "No site password is available to fill. Add credentials for this website in DynamicKey on your Mac first."
                    }
                } catch {
                    missingMessage = "Could not generate a new site password: \(error.localizedDescription)"
                }
            } else if let savedCredential = credentialStore.credential(forOrigin: fillRequest.origin) {
                fillCredentials = ExtensionFillCredentials(
                    username: savedCredential.username,
                    password: savedCredential.password
                )
            }

            if fillCredentials == nil, missingMessage == nil {
                switch intent {
                case .login:
                    missingMessage = "No site password saved for this website. Sign up on this site with DynamicKey first, or add credentials in Mac Settings."
                case .signup:
                    missingMessage = "No site password was created. Verify again on the sign-up form."
                case .changePassword:
                    missingMessage = "No site password is available to fill. Complete rhythm verify on the change-password form first."
                }
            }

            let response = ExtensionFillApproveResponse(
                protocolVersion: ExtensionAuthConfig.protocolVersion,
                requestId: fillRequest.requestId,
                approved: true,
                expiresAt: approval.expiresAt,
                message: missingMessage,
                credentials: fillCredentials
            )
            return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
        }

        let response = ExtensionFillApproveResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            requestId: fillRequest.requestId,
            approved: false,
            expiresAt: nil,
            message: "No recent successful verification for this origin.",
            credentials: nil
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Clears sign-in lockout for development and extension testing (auth required).
    private func handleResetLockout(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        profileStore.resetLockout()
        let response = ExtensionResetLockoutResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            cleared: true
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Reports whether an origin may use verify/autofill under the current allowlist policy.
    private func handleAllowlistCheck(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let checkRequest = decode(ExtensionAllowlistCheckRequest.self, from: request.body) else {
            return badRequest("Invalid allowlist check request JSON.")
        }

        guard checkRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard !checkRequest.origin.isEmpty else {
            return badRequest("Origin is required.")
        }

        let storageKey = SiteCredential.storageKey(for: checkRequest.origin)
        let allowedOrigins = sitePolicyStore.allowedOrigins()
        let allowlistActive = true
        let allowed = sitePolicyStore.isOriginAllowed(checkRequest.origin)

        let response = ExtensionAllowlistCheckResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            origin: checkRequest.origin,
            normalizedOrigin: storageKey,
            allowed: allowed,
            allowlistActive: allowlistActive
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Adds an origin to the allowlist after explicit user approval in the extension (W4.2).
    private func handleAllowlistAdd(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let addRequest = decode(ExtensionAllowlistAddRequest.self, from: request.body) else {
            return badRequest("Invalid allowlist add request JSON.")
        }

        guard addRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard !addRequest.origin.isEmpty else {
            return badRequest("Origin is required.")
        }

        let normalized = SiteCredential.storageKey(for: addRequest.origin)
        let alreadyAllowed = sitePolicyStore.isOriginAllowed(addRequest.origin)
        let alreadyListed = sitePolicyStore.allowedOrigins().contains {
            SiteCredential.sameSiteGroup($0, addRequest.origin)
        }

        if !alreadyAllowed {
            if alreadyListed {
                sitePolicyStore.setOriginEnabled(addRequest.origin, enabled: true)
            } else {
                sitePolicyStore.addAllowedOrigin(addRequest.origin)
            }
            auditLog.append(
                AuditEvent(
                    type: .extensionAllowlistAdded,
                    detail: normalized
                )
            )
        }

        let response = ExtensionAllowlistAddResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            added: !alreadyAllowed,
            normalizedOrigin: normalized,
            message: alreadyAllowed ? "This website is already protected." : nil
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Marks an origin as not allowed on the allowlist (red dot) after extension dismiss (W4.2).
    private func handleAllowlistIgnore(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let ignoreRequest = decode(ExtensionAllowlistIgnoreRequest.self, from: request.body) else {
            return badRequest("Invalid allowlist ignore request JSON.")
        }

        guard ignoreRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard !ignoreRequest.origin.isEmpty else {
            return badRequest("Origin is required.")
        }

        let normalized = SiteCredential.storageKey(for: ignoreRequest.origin)
        let wasIgnored = !sitePolicyStore.isOriginAllowed(ignoreRequest.origin)
        sitePolicyStore.ignoreOrigin(ignoreRequest.origin)

        if !wasIgnored {
            auditLog.append(
                AuditEvent(
                    type: .extensionAllowlistAdded,
                    detail: "\(normalized) (not allowed)"
                )
            )
        }

        let response = ExtensionAllowlistIgnoreResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            ignored: true,
            normalizedOrigin: normalized
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Adds a sender domain to DynamicShield trusted list after extension "This is Safe".
    private func handleDynamicShieldTrust(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let trustRequest = decode(ExtensionDynamicShieldTrustRequest.self, from: request.body) else {
            return badRequest("Invalid DynamicShield trust request JSON.")
        }

        guard trustRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        let normalized = DynamicShieldPolicyStore.normalizeSenderDomain(trustRequest.senderDomain)
        guard !normalized.isEmpty else {
            return badRequest("Sender domain is required.")
        }

        let wasActivelyTrusted = dynamicShieldPolicyStore.isSenderDomainTrusted(normalized)
        let onList = dynamicShieldPolicyStore.trustedSenderDomains().contains {
            DynamicShieldPolicyStore.sameSenderDomain($0, normalized)
        }

        let applyTrust = { [self] in
            if !onList {
                self.dynamicShieldPolicyStore.addTrustedSenderDomain(normalized)
                self.auditLog.append(
                    AuditEvent(
                        type: .extensionDynamicShieldTrusted,
                        detail: "Extension · @\(normalized)"
                    )
                )
            } else if !wasActivelyTrusted {
                self.dynamicShieldPolicyStore.setSenderDomainEnabled(normalized, enabled: true)
            }
        }

        if Thread.isMainThread {
            applyTrust()
        } else {
            DispatchQueue.main.sync(execute: applyTrust)
        }

        let response = ExtensionDynamicShieldTrustResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            added: !wasActivelyTrusted,
            normalizedSenderDomain: normalized,
            message: wasActivelyTrusted ? "This sender is already trusted." : nil
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Returns actively trusted DynamicShield sender domains for extension sync.
    private func handleDynamicShieldList(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let listRequest = decode(ExtensionDynamicShieldListRequest.self, from: request.body) else {
            return badRequest("Invalid DynamicShield list request JSON.")
        }

        guard listRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        let trusted = dynamicShieldPolicyStore.trustedSenderDomains().filter {
            dynamicShieldPolicyStore.isSenderDomainTrusted($0)
        }

        let response = ExtensionDynamicShieldListResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            trustedSenderDomains: trusted
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Records DynamicShield warning/dismiss events from the extension in Security Activity.
    private func handleDynamicShieldEvent(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let eventRequest = decode(ExtensionDynamicShieldEventRequest.self, from: request.body) else {
            return badRequest("Invalid DynamicShield event request JSON.")
        }

        guard eventRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        let normalized = DynamicShieldPolicyStore.normalizeSenderDomain(eventRequest.senderDomain ?? "")
        let detailParts = [
            normalized.isEmpty ? nil : "@\(normalized)",
            eventRequest.flagSummary?.isEmpty == false ? eventRequest.flagSummary : nil,
        ].compactMap { $0 }
        let detail = detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")

        let eventType: AuditEventType?
        switch eventRequest.event {
        case "warning_shown":
            eventType = .extensionDynamicShieldWarning
        case "dismissed":
            eventType = .extensionDynamicShieldDismissed
        default:
            eventType = nil
        }

        if let eventType {
            let logEvent = { [self] in
                self.auditLog.append(AuditEvent(type: eventType, detail: detail))
            }
            if Thread.isMainThread {
                logEvent()
            } else {
                DispatchQueue.main.sync(execute: logEvent)
            }
        }

        let response = ExtensionDynamicShieldEventResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            logged: eventType != nil
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Reports whether the Mac app has a saved credential for the page origin (popup hint).
    private func handleCredentialCheck(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let checkRequest = decode(ExtensionCredentialCheckRequest.self, from: request.body) else {
            return badRequest("Invalid credential check request JSON.")
        }

        guard checkRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        guard !checkRequest.origin.isEmpty else {
            return badRequest("Origin is required.")
        }

        let normalized = SiteCredential.storageKey(for: checkRequest.origin)
        let hasCredential = credentialStore.credential(forOrigin: normalized) != nil
        var displayHost = URL(string: normalized)?.host ?? normalized
        if displayHost.hasPrefix("www.") {
            displayHost = String(displayHost.dropFirst(4))
        }

        let response = ExtensionCredentialCheckResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            origin: checkRequest.origin,
            normalizedOrigin: normalized,
            hasCredential: hasCredential,
            displayHost: displayHost
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    /// Activates the Mac app and opens an extension-requested flow such as retrain typing profile.
    private func handleOpenApp(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }

        guard let openRequest = decode(ExtensionOpenAppRequest.self, from: request.body) else {
            return badRequest("Invalid open-app request JSON.")
        }

        guard openRequest.protocolVersion == ExtensionAuthConfig.protocolVersion else {
            return LocalHTTPParser.errorResponse(
                statusCode: 400,
                statusText: "Bad Request",
                error: "unsupported_protocol",
                message: "Expected protocol version \(ExtensionAuthConfig.protocolVersion)."
            )
        }

        let intent = openRequest.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard intent == "open" || intent == "retrain" else {
            return badRequest("Unsupported app intent.")
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if intent == "retrain" {
                NotificationCenter.default.post(name: .dynamicKeyExtensionOpenRetrain, object: nil)
            }
        }

        let response = ExtensionOpenAppResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            opened: true,
            intent: intent
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: response, encoder: encoder)
    }

    // MARK: - Auth helpers

    /// Reads Bearer token from Authorization header and validates it against paired clients.
    private func authorize(_ request: LocalHTTPRequest) -> PairedExtensionClient? {
        guard let header = request.headers["authorization"],
              header.lowercased().hasPrefix("bearer ") else {
            return nil
        }
        let token = String(header.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        return pairingStore.client(forAccessToken: token)
    }

    /// CORS preflight for browser extension fetch calls to localhost.
    private func preflightResponse() -> LocalHTTPResponse {
        LocalHTTPResponse(
            statusCode: 204,
            statusText: "No Content",
            headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "Authorization, Content-Type",
            ],
            body: Data()
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    private func badRequest(_ message: String) -> LocalHTTPResponse {
        LocalHTTPParser.errorResponse(
            statusCode: 400,
            statusText: "Bad Request",
            error: "bad_request",
            message: message
        )
    }

    private func unauthorized() -> LocalHTTPResponse {
        LocalHTTPParser.errorResponse(
            statusCode: 401,
            statusText: "Unauthorized",
            error: "unauthorized",
            message: "Valid extension access token required."
        )
    }

    /// Reads Safe Mode on the main actor — status may be requested from the HTTP worker thread.
    private struct SafeModeStatusSnapshot: Equatable {
        let active: Bool
        let expiresAt: Date?
        let formattedRemainingTime: String?
    }

    private func safeModeStatusOnMain() -> SafeModeStatusSnapshot {
        if Thread.isMainThread {
            return snapshotSafeMode()
        }
        return DispatchQueue.main.sync {
            snapshotSafeMode()
        }
    }

    @MainActor
    private func snapshotSafeMode() -> SafeModeStatusSnapshot {
        let store = SafeModeStore.shared
        store.refreshExpiryIfNeeded()
        return SafeModeStatusSnapshot(
            active: store.isActive,
            expiresAt: store.expiresAt,
            formattedRemainingTime: store.isActive ? store.formattedRemainingTime : nil
        )
    }

    private func handleSafeModeActivate(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }
        activateSafeModeOnMain()
        return safeModeHTTPResponse()
    }

    private func handleSafeModeDeactivate(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard authorize(request) != nil else {
            return unauthorized()
        }
        deactivateSafeModeOnMain()
        return safeModeHTTPResponse()
    }

    private func activateSafeModeOnMain() {
        runOnMainActor {
            SafeModeStore.shared.activate()
        }
    }

    private func deactivateSafeModeOnMain() {
        runOnMainActor {
            SafeModeStore.shared.deactivate()
        }
    }

    /// Runs `@MainActor` store work from the localhost HTTP thread so SwiftUI observes updates.
    private func runOnMainActor(_ work: @MainActor @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    private func safeModeHTTPResponse() -> LocalHTTPResponse {
        let snapshot = safeModeStatusOnMain()
        let remainingSeconds: Int?
        if snapshot.active, let expiresAt = snapshot.expiresAt {
            remainingSeconds = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.down)))
        } else {
            remainingSeconds = nil
        }
        let body = ExtensionSafeModeResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            active: snapshot.active,
            expiresAt: snapshot.expiresAt,
            remainingSeconds: remainingSeconds,
            formattedRemainingTime: snapshot.formattedRemainingTime
        )
        return LocalHTTPParser.jsonResponse(statusCode: 200, statusText: "OK", body: body, encoder: encoder)
    }
}

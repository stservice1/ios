//
//  LoginViewModel.swift
//  Everywhere
//
//  1:1 port of the Android app's LoginActivity.kt business logic: node-code
//  DNS TXT validation (with orchestrator-cache staleness checks), profile
//  creation via ProfileFactory, and the 3-strikes / 2-minute cooldown
//  lockout. LoginView binds to this instead of owning any of the logic
//  itself.
//

import Foundation

/// Mirrors Kotlin's `LoginActivity.ValidationResult` nested data class.
struct LoginValidationResult {
    let isValid: Bool
    let message: String
    let subscriptionUrl: String?

    init(isValid: Bool, message: String, subscriptionUrl: String? = nil) {
        self.isValid = isValid
        self.message = message
        self.subscriptionUrl = subscriptionUrl
    }
}

final class LoginViewModel: ObservableObject {
    @Published var nodeCode: String = "" {
        didSet {
            guard !isUpdatingNodeCode else { return }
            let upper = nodeCode.uppercased()
            if upper != nodeCode {
                isUpdatingNodeCode = true
                nodeCode = upper
                isUpdatingNodeCode = false
            }
            if !nodeCode.isEmpty {
                clearError()
            }
        }
    }
    private var isUpdatingNodeCode = false

    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var loginButtonVisible = true
    @Published private(set) var cooldownText: String?
    /// Set when profile creation fails after 3 attempts — mirrors Android's
    /// "Connection Failed" AlertDialog with a "Copy Details" button.
    @Published var debugDetails: String?

    private var failedAttempts = 0
    private var cooldownEndTime: TimeInterval = 0
    private var countdownTimer: Timer?

    private let prefs = UserDefaults(suiteName: "login_lockout_prefs")!
    private static let keyFailedAttempts = "failed_attempts"
    private static let keyCooldownEnd = "cooldown_end"
    private static let cooldownDuration: TimeInterval = 120 // 2 minutes, matches COOLDOWN_DURATION_MS

    private let tag = "LoginActivity"

    deinit {
        countdownTimer?.invalidate()
    }

    /// Mirrors `LoginActivity.onCreate`'s lockout-state restore + pending
    /// orchestrator error message check.
    func onAppear() {
        Log.d(tag, "Creating LoginActivity")

        failedAttempts = prefs.integer(forKey: Self.keyFailedAttempts)
        cooldownEndTime = prefs.double(forKey: Self.keyCooldownEnd)
        let now = Date().timeIntervalSince1970
        if cooldownEndTime > now {
            loginButtonVisible = false
            startCooldownTimer(remaining: cooldownEndTime - now)
        } else {
            loginButtonVisible = true
            cooldownText = nil
            cancelCooldownTimer()
        }

        if let orchestratorError = STServiceOrchestrator.shared.getErrorMessage() {
            Log.d(tag, "Showing orchestrator error message: \(orchestratorError)")
            errorMessage = orchestratorError
            STServiceOrchestrator.shared.clearErrorMessage()
        }
    }

    func onDisappear() {
        cancelCooldownTimer()
    }

    private func showError(_ message: String) {
        errorMessage = message
    }

    private func clearError() {
        errorMessage = nil
    }

    /// Mirrors the login button's click handler. Returns true on success —
    /// LoginView switches to STMainView when this returns true.
    @discardableResult
    func login() async -> Bool {
        let code = nodeCode.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.d(tag, "Login button clicked with node code: \(code)")

        guard !code.isEmpty else {
            showError("Please enter a node code")
            return false
        }

        clearError()

        Log.d(tag, "Starting validation for node code: \(code)")

        // Hide the button without collapsing its space, to prevent layout
        // jump — mirrors View.INVISIBLE (LoginView keeps the button's frame
        // and just hides/disables it).
        loginButtonVisible = false
        cooldownText = nil
        isLoading = true

        let outcome: String?
        do {
            outcome = try await withTimeoutOrNil(seconds: 60) { [weak self] in
                guard let self else { return "error" }
                return await self.runValidationAndCreateProfile(nodeCode: code)
            }
        } catch {
            Log.e(tag, "Login error: \(error.localizedDescription)", error)
            showError("Login error: \(error.localizedDescription)")
            outcome = "error"
        }

        if outcome == nil {
            Log.w(tag, "Login process timed out after 60 seconds")
            showError("Something went wrong, please try again")
        }

        // Always restore UI.
        isLoading = false
        if cooldownEndTime > Date().timeIntervalSince1970 {
            loginButtonVisible = false
        } else {
            loginButtonVisible = true
            cooldownText = nil
        }

        return outcome == "success"
    }

    private func runValidationAndCreateProfile(nodeCode: String) async -> String {
        let validationResult = await validateNodeCode(nodeCode)
        Log.d(tag, "Validation result: \(validationResult.isValid), message: \(validationResult.message)")

        if validationResult.isValid, let subscriptionUrl = validationResult.subscriptionUrl {
            Log.d(tag, "Creating profile with URL: \(subscriptionUrl)")
            let succeeded = await createProfile(nodeCode: nodeCode, subscriptionUrl: subscriptionUrl)
            return succeeded ? "success" : "error"
        } else {
            Log.w(tag, "Validation failed: \(validationResult.message)")
            showError(validationResult.message)
            handleValidationFailure(validationResult.message)
            return "validation_failed"
        }
    }

    // MARK: - Node code validation (AliDNS TXT lookup)

    private func validateNodeCode(_ nodeCode: String) async -> LoginValidationResult {
        do {
            let lastTwoDigits = String(nodeCode.suffix(2))
            let domain = "\(nodeCode).stservice\(lastTwoDigits).ddnsfree.com"
            Log.d(tag, "Making DNS query for: \(domain)")
            let urlString = "https://dns.alidns.com/resolve?name=\(domain)&type=TXT"

            let response = try await DNSTXTClient.get(urlString, timeout: 10)
            Log.d(tag, "DNS query response code: \(response.statusCode)")

            if response.statusCode == 200 {
                Log.d(tag, "DNS response: \(response.body)")

                guard let data = response.body.data(using: .utf8) else {
                    throw NSError(domain: "LoginActivity", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response encoding"])
                }
                let jsonResponse = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                guard let status = (jsonResponse["Status"] as? NSNumber)?.intValue else {
                    throw NSError(domain: "LoginActivity", code: -1, userInfo: [NSLocalizedDescriptionKey: "missing Status field"])
                }

                if status == 0, let answers = jsonResponse["Answer"] as? [[String: Any]], !answers.isEmpty {
                    let txtData = answers[0]["data"] as? String ?? ""
                    Log.d(tag, "TXT record data: \(txtData)")

                    let txtInfo = TXTRecordParser.parseTXTData(txtData)

                    // Use cache-aware logic through the orchestrator.
                    let orchestrator = STServiceOrchestrator.shared
                    let cachedTxtInfo = orchestrator.getCachedTxtRecordForLogin(nodeCode: nodeCode)

                    let finalTxtInfo: TXTRecordInfo
                    if let cachedTxtInfo, !txtData.isEmpty {
                        if txtInfo.modified <= cachedTxtInfo.modified {
                            Log.d(tag, "DNS returned stale data (\(txtInfo.modified) <= \(cachedTxtInfo.modified)), using cached")
                            finalTxtInfo = cachedTxtInfo
                        } else {
                            Log.d(tag, "DNS returned fresh data (\(txtInfo.modified) > \(cachedTxtInfo.modified)), updating cache")
                            orchestrator.cacheTxtRecordForLogin(txtInfo, nodeCode: nodeCode)
                            finalTxtInfo = txtInfo
                        }
                    } else {
                        Log.d(tag, "No cached data available, using fresh DNS data")
                        orchestrator.cacheTxtRecordForLogin(txtInfo, nodeCode: nodeCode)
                        finalTxtInfo = txtInfo
                    }

                    return validateTxtRecord(finalTxtInfo)
                }
            }

            Log.w(tag, "Node code not found in DNS")
            return LoginValidationResult(isValid: false, message: "Node code not found")
        } catch {
            Log.e(tag, "Network error during validation: \(error.localizedDescription)", error)
            return LoginValidationResult(isValid: false, message: "Network error: \(error.localizedDescription)")
        }
    }

    private func validateTxtRecord(_ txtInfo: TXTRecordInfo) -> LoginValidationResult {
        Log.d(tag, "Validating TXT record: \(txtInfo)")

        if txtInfo.consumed {
            Log.w(tag, "Node code has already been used")
            return LoginValidationResult(isValid: false, message: "This node code has already been used")
        }

        if txtInfo.banned {
            Log.w(tag, "Node code is banned")
            return LoginValidationResult(isValid: false, message: STServiceOrchestrator.loginErrorBanned)
        }

        if TXTRecordParser.isExpired(txtInfo) {
            Log.w(tag, "Node code has expired: \(String(describing: txtInfo.expiration))")
            return LoginValidationResult(isValid: false, message: STServiceOrchestrator.loginErrorExpired)
        }

        guard let vpnUrl = txtInfo.vpnUrl, !vpnUrl.isEmpty else {
            Log.w(tag, "No subscription URL found in TXT record")
            return LoginValidationResult(isValid: false, message: "Invalid node code: missing subscription URL")
        }

        Log.d(tag, "Node code validation successful")
        return LoginValidationResult(isValid: true, message: "Success", subscriptionUrl: vpnUrl)
    }

    // MARK: - Profile creation

    /// Returns true on success. On failure, sets `errorMessage` (and
    /// `debugDetails` if it was a subscription-fetch failure) itself,
    /// mirroring LoginActivity.createProfile's own error UI handling.
    private func createProfile(nodeCode: String, subscriptionUrl: String) async -> Bool {
        do {
            Log.d(tag, "Creating profile with subscription URL: \(subscriptionUrl)")
            try await ProfileFactory.createProfile(nodeCode: nodeCode, subscriptionUrl: subscriptionUrl)

            Log.d(tag, "Profile setup complete, launching MainActivity")

            let orchestrator = STServiceOrchestrator.shared
            orchestrator.setLoginStatus(true)
            orchestrator.clearErrorMessage()

            // Android shows a "Login successful!" Toast here, but
            // immediately navigates away in the same breath — there's
            // nothing left on screen long enough for a toast to matter, so
            // it isn't reproduced.
            return true
        } catch {
            Log.e(tag, "Error creating profile: \(error.localizedDescription)", error)
            if let detailed = error as? ProfileFactory.DetailedFailure {
                debugDetails = detailed.debugInfo
            }
            showError("Error creating profile: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Cooldown lockout

    private func handleValidationFailure(_ message: String) {
        // Count attempts for all validation failures that are not
        // network/timeouts.
        let countsTowardsLimit =
            message == STServiceOrchestrator.loginErrorBanned ||
            message.range(of: "already been used", options: .caseInsensitive) != nil ||
            message == "Node code not found" ||
            message.lowercased().hasPrefix("invalid node code")

        guard countsTowardsLimit else { return }

        failedAttempts += 1
        prefs.set(failedAttempts, forKey: Self.keyFailedAttempts)
        if failedAttempts >= 3 {
            failedAttempts = 0
            prefs.set(failedAttempts, forKey: Self.keyFailedAttempts)
            startCooldownTimer(remaining: Self.cooldownDuration)
        }
    }

    private func startCooldownTimer(remaining: TimeInterval) {
        cancelCooldownTimer()
        cooldownEndTime = Date().timeIntervalSince1970 + remaining
        prefs.set(cooldownEndTime, forKey: Self.keyCooldownEnd)

        loginButtonVisible = false
        // Keep the error message visible, do not overwrite it.

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let remainingNow = self.cooldownEndTime - Date().timeIntervalSince1970
            if remainingNow <= 0 {
                self.loginButtonVisible = true
                self.cooldownEndTime = 0
                self.prefs.set(0.0, forKey: Self.keyCooldownEnd)
                self.cooldownText = nil
                self.countdownTimer = nil
                timer.invalidate()
            } else {
                let mm = Int(remainingNow) / 60
                let ss = Int(remainingNow) % 60
                self.cooldownText = String(format: "Please wait %02d:%02d to try again", mm, ss)
            }
        }
    }

    private func cancelCooldownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

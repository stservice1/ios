//
//  STServiceOrchestrator.swift
//  Everywhere
//
//  1:1 port of the Android app's service/STServiceOrchestrator.kt: login
//  status, cached TXT-record lookups, Dynu "consumed" status updates,
//  profile-link mismatch detection/rebuild, logout, and periodic
//  ban/expiration/link monitoring.
//
//  Platform substitutions (everything else below is ported verbatim):
//  - Android's per-profile AIDL "Profile" store -> ConfigurationStore,
//    filtered to `.mihomo` (STVPN is a single-engine app; Android's Clash
//    fork only ever has one engine, so "all profiles" there maps to
//    "all mihomo configurations" here).
//  - Android's WorkManager periodic work (survives backgrounding) ->
//    a foreground `Timer` on the same 15-minute interval. This only
//    covers the app being open, not backgrounded/killed — iOS has no
//    drop-in equivalent without BGTaskScheduler (separate background-modes
//    registration), so this is flagged rather than silently dropped.
//  - `redirectToLogin` (Android: relaunch LoginActivity) -> a
//    NotificationCenter post that STRootView observes to switch back to
//    LoginView.
//

import Foundation

extension Notification.Name {
    /// Posted by `logout(errorMessage:)` — STRootView observes this to
    /// switch back to LoginView, mirroring Android's
    /// `redirectToLogin` (relaunching LoginActivity with CLEAR_TASK).
    static let stvpnRedirectToLogin = Notification.Name("STVPNRedirectToLogin")
}

/// Mirrors Kotlin's `class ProfileUpdateException(message: String) : Exception(message)`.
struct ProfileUpdateException: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class STServiceOrchestrator {
    static let shared = STServiceOrchestrator()
    private init() {}

    // MARK: - Constants (mirrors the Kotlin companion object)

    private static let prefsSuiteName = "st_service_prefs"
    private static let keyLoginStatus = "login_status"
    private static let keyLastCheck = "last_check"
    private static let keyErrorMessage = "error_message"
    private static let keyCachedTxtRecord = "cached_txt_record"
    private static let keyCachedNodeCode = "cached_node_code"
    private static let keyDynuApiKey = "dynu_api_key"

    private static let dynuApiBaseURL = "https://api.dynu.com/v2/dns"
    private static let checkIntervalSeconds: TimeInterval = 15 * 60 // WorkManager minimum

    private static let profileOpMaxAttempts = 5
    private static let profileOpRetryDelayNanos: UInt64 = 1_000_000_000

    static let loginErrorExpired = "Your node code has expired, please contact ST Service to buy a new node code for a new time period."
    static let loginErrorBanned = "You have been banned"
    static let loginErrorNetwork = "Network error during validation"

    private let tag = "STServiceOrchestrator"
    private let linkTag = "LINK_UPDATE"

    private var prefs: UserDefaults { UserDefaults(suiteName: Self.prefsSuiteName)! }

    private var monitoringTimer: Timer?

    // MARK: - Monitoring

    /// Mirrors `startMonitoring(context)`. See the platform-substitution
    /// note at the top of this file re: WorkManager vs. foreground Timer.
    func startMonitoring() {
        Log.d(tag, "Starting ST Service monitoring")
        monitoringTimer?.invalidate()
        let timer = Timer(timeInterval: Self.checkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { await self?.runMonitoringCheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitoringTimer = timer
    }

    func stopMonitoring() {
        Log.d(tag, "Stopping ST Service monitoring")
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    /// Mirrors `MonitoringWorker.doWork()`.
    private func runMonitoringCheck() async {
        Log.d(tag, "Running monitoring check")

        guard isLoggedIn() else {
            Log.d(tag, "User not logged in, skipping check")
            return
        }

        let hasProfiles = await MainActor.run {
            !ConfigurationStore.shared.configurations.filter { $0.coreType == .mihomo }.isEmpty
        }
        guard hasProfiles else {
            Log.d(tag, "No user profiles found, user appears logged out - skipping check")
            stopMonitoring()
            setLoginStatus(false)
            return
        }

        guard let txtInfo = await fetchTXTRecordWithCache() else {
            Log.w(tag, "Failed to check TXT record")
            return
        }

        prefs.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: Self.keyLastCheck)

        if txtInfo.banned {
            Log.w(tag, "User has been banned")
            await logout(errorMessage: Self.loginErrorBanned)
            return
        }

        if let expiration = txtInfo.expiration, Date() > expiration {
            Log.w(tag, "Node code has expired: \(expiration)")
            await logout(errorMessage: Self.loginErrorExpired)
            return
        }

        if let newLink = txtInfo.link {
            do {
                let linkChanged = try await checkAndUpdateLink(newLink: newLink)
                if linkChanged {
                    Log.d(tag, "Profile link updated successfully")
                }
            } catch {
                Log.e(tag, "Error updating profile link", error)
            }
        }

        Log.d(tag, "Monitoring check passed")
    }

    // MARK: - Login status / error message

    func setLoginStatus(_ isLoggedIn: Bool) {
        prefs.set(isLoggedIn, forKey: Self.keyLoginStatus)
    }

    func isLoggedIn() -> Bool {
        prefs.bool(forKey: Self.keyLoginStatus)
    }

    func setErrorMessage(_ message: String?) {
        if let message {
            prefs.set(message, forKey: Self.keyErrorMessage)
        } else {
            prefs.removeObject(forKey: Self.keyErrorMessage)
        }
    }

    func getErrorMessage() -> String? {
        prefs.string(forKey: Self.keyErrorMessage)
    }

    func clearErrorMessage() {
        setErrorMessage(nil)
    }

    // MARK: - TXT record cache (login-flow entry points)

    func getCachedTxtRecordForLogin(nodeCode: String) -> TXTRecordInfo? {
        getCachedTxtRecord(nodeCode: nodeCode)
    }

    func cacheTxtRecordForLogin(_ txtInfo: TXTRecordInfo, nodeCode: String) {
        cacheTxtRecord(txtInfo, nodeCode: nodeCode)
    }

    // MARK: - Dynu API key

    func setDynuApiKey(_ apiKey: String) {
        prefs.set(apiKey, forKey: Self.keyDynuApiKey)
        Log.d(tag, "Dynu API key stored")
    }

    private func getDynuApiKey() -> String? {
        prefs.string(forKey: Self.keyDynuApiKey)
    }

    // MARK: - Consumed status (Dynu API)

    func updateConsumedStatus(_ txtInfo: TXTRecordInfo, onError: ((String) async -> Void)? = nil) async {
        guard let nodeCode = await getNodeCodeFromActiveProfile() else {
            Log.w(tag, "No node code found for consumed update")
            await failConsumedUpdate(message: "No node code found - cannot update consumed status", onError: onError)
            return
        }

        guard let apiKey = getDynuApiKey(), !apiKey.isEmpty else {
            Log.w(tag, "No Dynu API key configured - cannot update consumed status")
            await failConsumedUpdate(message: "No API key configured - cannot update consumed status", onError: onError)
            return
        }

        guard txtInfo.domainId != 0, txtInfo.recordId != 0 else {
            Log.w(tag, "Missing domain_id or record_id - cannot update consumed status")
            await failConsumedUpdate(message: "Missing domain_id or record_id - cannot update consumed status", onError: onError)
            return
        }

        Log.d(tag, "Updating consumed=true via Dynu API for node: \(nodeCode)")

        let updatedJson = createUpdatedTxtRecord(txtInfo, consumed: true)
        let statusCode = await callDynuApiToUpdateRecord(
            apiKey: apiKey, domainId: txtInfo.domainId, recordId: txtInfo.recordId,
            nodeCode: nodeCode, textData: updatedJson
        )

        if statusCode == 200 {
            Log.d(tag, "Successfully updated consumed=true via Dynu API")
            var updated = txtInfo
            updated.consumed = true
            updated.modified = Int64(Date().timeIntervalSince1970)
            cacheTxtRecord(updated, nodeCode: nodeCode)
        } else {
            Log.w(tag, "Failed to update consumed status via Dynu API")
            await failConsumedUpdate(message: "Failed to update consumed status via API. Status code: \(statusCode)", onError: onError)
        }
    }

    /// Stops the VPN and reports `message` to the caller when a
    /// consumed-status update cannot proceed.
    private func failConsumedUpdate(message: String, onError: ((String) async -> Void)?) async {
        await ClashServiceBridge.stopClashService()
        await onError?(message)
    }

    private func createUpdatedTxtRecord(_ txtInfo: TXTRecordInfo, consumed: Bool) -> String {
        func orNull(_ v: Any?) -> Any { v ?? NSNull() }
        let dict: [String: Any] = [
            "v": txtInfo.version,
            "b": txtInfo.banned,
            "e": orNull(txtInfo.expiration.map { TXTRecordParser.dateFormatter.string(from: $0) }),
            "c": consumed,
            "m": Int64(Date().timeIntervalSince1970),
            "u": orNull(txtInfo.vpnUrl),
            "d": txtInfo.domainId,
            "r": txtInfo.recordId,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func callDynuApiToUpdateRecord(apiKey: String, domainId: Int64, recordId: Int64, nodeCode: String, textData: String) async -> Int {
        do {
            guard let url = URL(string: "\(Self.dynuApiBaseURL)/\(domainId)/record/\(recordId)") else { return -1 }

            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "API-Key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody: [String: Any] = [
                "nodeName": nodeCode,
                "recordType": "TXT",
                "ttl": 60,
                "state": true,
                "textData": textData,
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = bodyData

            Log.d(tag, "Dynu API request: \(String(data: bodyData, encoding: .utf8) ?? "")")

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "No error details"

            Log.d(tag, "Dynu API response code: \(statusCode)")
            Log.d(tag, "Dynu API response body: \(responseBody)")

            return statusCode
        } catch {
            Log.e(tag, "Error calling Dynu API", error)
            return -1
        }
    }

    // MARK: - TXT record cache (private)

    private func cacheTxtRecord(_ txtInfo: TXTRecordInfo, nodeCode: String) {
        let jsonString = serializeTxtRecord(txtInfo)
        prefs.set(jsonString, forKey: Self.keyCachedTxtRecord)
        prefs.set(nodeCode, forKey: Self.keyCachedNodeCode)
        Log.d(tag, "Cached TXT record for node \(nodeCode) with modified timestamp: \(txtInfo.modified)")
    }

    /// Returns the cached TXT record only if it belongs to `nodeCode`. The
    /// cache is a single slot shared between the login flow (where the user
    /// may probe several different node codes) and active-profile
    /// monitoring, so without this check a record cached for one node code
    /// could be mistaken for stale/duplicate data of a completely different one.
    private func getCachedTxtRecord(nodeCode: String) -> TXTRecordInfo? {
        guard prefs.string(forKey: Self.keyCachedNodeCode) == nodeCode,
              let jsonString = prefs.string(forKey: Self.keyCachedTxtRecord) else { return nil }
        return deserializeTxtRecord(jsonString)
    }

    private func serializeTxtRecord(_ txtInfo: TXTRecordInfo) -> String {
        func orNull(_ v: Any?) -> Any { v ?? NSNull() }
        let dict: [String: Any] = [
            "v": txtInfo.version,
            "b": txtInfo.banned,
            "e": orNull(txtInfo.expiration.map { TXTRecordParser.dateFormatter.string(from: $0) }),
            "c": txtInfo.consumed,
            "m": txtInfo.modified,
            "u": orNull(txtInfo.vpnUrl),
            "d": txtInfo.domainId,
            "r": txtInfo.recordId,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func deserializeTxtRecord(_ jsonString: String) -> TXTRecordInfo? {
        guard let data = jsonString.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.e(tag, "Error deserializing cached TXT record")
            return nil
        }

        let version = (json["v"] as? NSNumber)?.intValue ?? 1
        let banned = (json["b"] as? Bool) ?? false
        let consumed = (json["c"] as? Bool) ?? false
        let modified = (json["m"] as? NSNumber)?.int64Value ?? 0
        let vpnUrl = json["u"] as? String ?? ""
        let domainId = (json["d"] as? NSNumber)?.int64Value ?? 0
        let recordId = (json["r"] as? NSNumber)?.int64Value ?? 0

        var expiration: Date?
        let expirationStr = json["e"] as? String ?? ""
        if !expirationStr.isEmpty, expirationStr != "null" {
            expiration = TXTRecordParser.dateFormatter.date(from: expirationStr)
        }

        return TXTRecordInfo(
            version: version, banned: banned, expiration: expiration, consumed: consumed,
            modified: modified, vpnUrl: vpnUrl.isEmpty ? nil : vpnUrl,
            domainId: domainId, recordId: recordId
        )
    }

    // MARK: - Node code lookup

    private func getNodeCodeFromActiveProfile() async -> String? {
        await MainActor.run {
            let store = ConfigurationStore.shared
            let regex = try! NSRegularExpression(pattern: "\\(([^)]+)\\)")

            func extractNodeCode(from name: String) -> String? {
                let range = NSRange(name.startIndex..., in: name)
                guard let match = regex.firstMatch(in: name, range: range), match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: name) else { return nil }
                return String(name[r])
            }

            // First try to get node code from the active profile.
            let activeID = store.activeIDByCoreType[.mihomo]
            if let activeProfile = store.configurations.first(where: { $0.id == activeID }),
               let code = extractNodeCode(from: activeProfile.name) {
                return code
            }

            // If no active profile or node code not found, try all
            // profiles — handles the case where the profile failed and
            // became inactive.
            for profile in store.configurations.filter({ $0.coreType == .mihomo }) {
                if let code = extractNodeCode(from: profile.name) {
                    Log.d(tag, "Found node code '\(code)' from inactive profile: \(profile.name)")
                    return code
                }
            }

            return nil
        }
    }

    // MARK: - Immediate check (testing only — kept for parity, unused in production)

    func performImmediateCheck() async {
        Log.d(tag, "Performing immediate check for testing")

        guard isLoggedIn() else {
            Log.d(tag, "User not logged in, skipping immediate check")
            return
        }

        guard let txtInfo = await fetchTXTRecordWithCache() else {
            Log.w(tag, "Failed to check TXT record in immediate check")
            return
        }

        if txtInfo.banned {
            Log.w(tag, "User has been banned (immediate check)")
            await logout(errorMessage: Self.loginErrorBanned)
            return
        }

        if let expiration = txtInfo.expiration, Date() > expiration {
            Log.w(tag, "Node code has expired (immediate check): \(expiration)")
            await logout(errorMessage: Self.loginErrorExpired)
            return
        }

        Log.d(tag, "Immediate check passed - no issues found")
    }

    // MARK: - Logout

    func logout(errorMessage: String? = nil) async {
        Log.d(tag, "Logging out user, stopping service and deleting all profiles")

        stopMonitoring()

        Log.d(tag, "Stopping Clash service")
        await ClashServiceBridge.stopClashService()

        await MainActor.run {
            let store = ConfigurationStore.shared
            let profiles = store.configurations.filter { $0.coreType == .mihomo }
            Log.d(tag, "Found \(profiles.count) profiles to delete")
            for profile in profiles {
                Log.d(tag, "Deleting profile: \(profile.name) (\(profile.id))")
                store.delete(profile)
                Log.d(tag, "Successfully deleted profile: \(profile.id)")
            }

            let remaining = store.configurations.filter { $0.coreType == .mihomo }
            if remaining.isEmpty {
                Log.d(tag, "All profiles deleted successfully")
            } else {
                Log.w(tag, "Warning: \(remaining.count) profiles still remain after logout")
                for r in remaining {
                    Log.w(tag, "Remaining profile: \(r.name) (\(r.id))")
                }
            }
        }

        setLoginStatus(false)
        if let errorMessage {
            setErrorMessage(errorMessage)
        }

        redirectToLogin()
    }

    func redirectToLogin() {
        NotificationCenter.default.post(name: .stvpnRedirectToLogin, object: nil)
    }

    // MARK: - Link mismatch detection / rebuild

    /// Rebuilds all local profiles to point at `newLink` when a mismatch is
    /// detected. Throws `ProfileUpdateException` if a delete or create
    /// cannot be confirmed against the actual profile store after
    /// `profileOpMaxAttempts` attempts; callers should surface that to the
    /// user.
    ///
    /// `onProfileUpdateStart`/`onProfileUpdateEnd` fire only when a rebuild
    /// is actually happening, so callers can drive UI feedback (e.g.
    /// disable the start/stop button) without this class depending on any
    /// UI layer.
    func checkAndUpdateLink(
        newLink: String,
        onProfileUpdateStart: (() async -> Void)? = nil,
        onProfileUpdateEnd: (() async -> Void)? = nil
    ) async throws -> Bool {
        Log.d(linkTag, "===== START LINK CHECK =====")
        Log.d(linkTag, "New link from AliDNS: \(newLink)")

        let wasServiceRunning = await MainActor.run { ClashServiceBridge.isServiceRunning() }
        Log.d(linkTag, "Service running status: \(wasServiceRunning)")

        let profiles = await MainActor.run {
            ConfigurationStore.shared.configurations.filter { $0.coreType == .mihomo }
        }
        Log.d(linkTag, "Total profiles found: \(profiles.count)")
        for profile in profiles {
            Log.d(linkTag, "  Profile: \(profile.name) (\(profile.id)) source=\(profile.sourceURL ?? "nil")")
        }

        if !profiles.isEmpty, profiles.allSatisfy({ $0.sourceURL == newLink }) {
            Log.d(linkTag, "Profile link matches - no update needed")
            Log.d(linkTag, "===== END LINK CHECK =====")
            return false
        }

        Log.d(linkTag, "LINK MISMATCH DETECTED - rebuilding profile(s)")
        Log.d(linkTag, "  New link: \(newLink)")

        // Preserve the name of the profile being replaced.
        let activeID = await MainActor.run { ConfigurationStore.shared.activeIDByCoreType[.mihomo] }
        let template = profiles.first(where: { $0.id == activeID }) ?? profiles.first
        let profileName = template?.name ?? "ST VPN Service"

        await onProfileUpdateStart?()
        do {
            if wasServiceRunning {
                Log.d(linkTag, "Stopping service for link update...")
                await ClashServiceBridge.stopClashService()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            // Delete every existing profile, confirming each deletion
            // against the real profile store.
            for profile in profiles {
                try await deleteProfileWithRetry(profile.id)
            }

            // Create the replacement profile, confirming it against the
            // real profile store.
            let newConfig = try await createProfileWithRetry(name: profileName, link: newLink)

            let updatedProfile = await MainActor.run {
                ConfigurationStore.shared.configurations.first(where: { $0.id == newConfig.id })
            }
            Log.d(linkTag, "===== PROFILE AFTER UPDATE =====")
            Log.d(linkTag, "Profile name: \(updatedProfile?.name ?? "nil")")
            Log.d(linkTag, "Profile UUID: \(updatedProfile?.id.uuidString ?? "nil")")
            Log.d(linkTag, "Updated profile.source: \(updatedProfile?.sourceURL ?? "nil")")
            Log.d(linkTag, "Profile imported: \(updatedProfile?.imported ?? false)")

            if let updatedProfile {
                await MainActor.run { ConfigurationStore.shared.setActive(updatedProfile) }
                Log.d(linkTag, "Profile set as active")
            }

            // Restart the service if it was running before AND the profile
            // imported successfully.
            if wasServiceRunning {
                if updatedProfile?.imported == true {
                    Log.d(linkTag, "Profile imported successfully, restarting service...")
                    await ClashServiceBridge.startClashService()
                    Log.d(linkTag, "Service restarted successfully")
                } else {
                    Log.w(linkTag, "Profile not imported (fetch failed), service will remain stopped")
                    Log.w(linkTag, "User can manually start VPN once link is fixed")
                }
            }

            Log.d(linkTag, "===== END LINK CHECK =====")
            Log.d(linkTag, "Profile was updated: SUCCESS")
            await onProfileUpdateEnd?()
            return true
        } catch {
            Log.e(linkTag, "ERROR during link check/update: \(error.localizedDescription)", error)
            await onProfileUpdateEnd?()
            throw error
        }
    }

    /// Deletes the profile with `id` and confirms the deletion by
    /// re-querying the actual profile store (not just trusting that the
    /// delete call didn't throw).
    private func deleteProfileWithRetry(_ id: UUID) async throws {
        for attempt in 1...Self.profileOpMaxAttempts {
            Log.d(linkTag, "Delete attempt \(attempt)/\(Self.profileOpMaxAttempts) for profile \(id)")

            await MainActor.run {
                if let existing = ConfigurationStore.shared.configurations.first(where: { $0.id == id }) {
                    ConfigurationStore.shared.delete(existing)
                }
            }

            try? await Task.sleep(nanoseconds: Self.profileOpRetryDelayNanos)

            if await isProfileDeleted(id) {
                Log.d(linkTag, "Profile \(id) confirmed deleted")
                return
            }

            Log.w(linkTag, "Profile \(id) still present after attempt \(attempt)")
        }

        throw ProfileUpdateException("Failed to delete profile \(id) after \(Self.profileOpMaxAttempts) attempts")
    }

    /// Queries the real profile store to confirm `id` no longer exists.
    private func isProfileDeleted(_ id: UUID) async -> Bool {
        await MainActor.run {
            !ConfigurationStore.shared.configurations.contains(where: { $0.id == id })
        }
    }

    /// Creates a profile pointed at `link` and confirms it via
    /// `isProfileCreatedWithLink` against the actual profile store before
    /// trusting it, retrying on failure.
    private func createProfileWithRetry(name: String, link: String) async throws -> Configuration {
        for attempt in 1...Self.profileOpMaxAttempts {
            Log.d(linkTag, "Create attempt \(attempt)/\(Self.profileOpMaxAttempts) for link \(link)")

            let cfg = await MainActor.run {
                ConfigurationStore.shared.create(name: name, type: .mihomo, content: "", sourceURL: link)
            }

            do {
                guard let linkURL = URL(string: link) else { throw URLError(.badURL) }
                let content = try await SubscriptionFetcher.fetch(from: linkURL)
                await MainActor.run { ConfigurationStore.shared.update(cfg, content: content) }
            } catch {
                Log.e(linkTag, "commit/update failed on attempt \(attempt) for profile \(cfg.id)", error)
            }

            try? await Task.sleep(nanoseconds: Self.profileOpRetryDelayNanos)

            if await isProfileCreatedWithLink(cfg.id, expectedLink: link) {
                Log.d(linkTag, "Profile \(cfg.id) confirmed created with correct link")
                return cfg
            }

            Log.w(linkTag, "Profile \(cfg.id) failed validation after attempt \(attempt), discarding before retry")
            await MainActor.run {
                if let existing = ConfigurationStore.shared.configurations.first(where: { $0.id == cfg.id }) {
                    ConfigurationStore.shared.delete(existing)
                }
            }
        }

        throw ProfileUpdateException("Failed to create profile for link \(link) after \(Self.profileOpMaxAttempts) attempts")
    }

    /// Queries the real profile store to confirm `id` exists with the
    /// expected link.
    private func isProfileCreatedWithLink(_ id: UUID, expectedLink: String) async -> Bool {
        await MainActor.run {
            guard let profile = ConfigurationStore.shared.configurations.first(where: { $0.id == id }) else { return false }
            return profile.sourceURL == expectedLink
        }
    }

    // MARK: - TXT record fetch (with cache)

    func fetchTXTRecordWithMandatoryCheck() async throws -> TXTRecordInfo? {
        guard let nodeCode = await getNodeCodeFromActiveProfile() else {
            Log.w(tag, "No node code found in active profile")
            return nil
        }

        let cachedTxt = getCachedTxtRecord(nodeCode: nodeCode)
        let freshTxt = try await checkTXTRecordMandatory(nodeCode: nodeCode)

        if let cachedTxt, let freshTxt {
            if freshTxt.modified <= cachedTxt.modified {
                Log.d(tag, "DNS returned stale data (\(freshTxt.modified) <= \(cachedTxt.modified)), using cached")
                return cachedTxt
            } else {
                Log.d(tag, "DNS returned fresh data (\(freshTxt.modified) > \(cachedTxt.modified)), updating cache")
                cacheTxtRecord(freshTxt, nodeCode: nodeCode)
                return freshTxt
            }
        } else if let freshTxt {
            Log.d(tag, "No cached data, using fresh DNS data (\(freshTxt.modified))")
            cacheTxtRecord(freshTxt, nodeCode: nodeCode)
            return freshTxt
        } else if cachedTxt != nil {
            Log.w(tag, "DNS fetch failed, but this is mandatory - not using cached data")
            return nil
        } else {
            Log.w(tag, "No cached or fresh data available for mandatory check")
            return nil
        }
    }

    func fetchTXTRecordWithCache() async -> TXTRecordInfo? {
        guard let nodeCode = await getNodeCodeFromActiveProfile() else {
            Log.w(tag, "No node code found in active profile")
            return nil
        }

        let cachedTxt = getCachedTxtRecord(nodeCode: nodeCode)
        let freshTxt = await checkTXTRecord(nodeCode: nodeCode)

        if let cachedTxt, let freshTxt {
            if freshTxt.modified <= cachedTxt.modified {
                Log.d(tag, "DNS returned stale data (\(freshTxt.modified) <= \(cachedTxt.modified)), using cached")
                return cachedTxt
            } else {
                Log.d(tag, "DNS returned fresh data (\(freshTxt.modified) > \(cachedTxt.modified)), updating cache")
                cacheTxtRecord(freshTxt, nodeCode: nodeCode)
                return freshTxt
            }
        } else if let freshTxt {
            Log.d(tag, "No cached data, using fresh DNS data (\(freshTxt.modified))")
            cacheTxtRecord(freshTxt, nodeCode: nodeCode)
            return freshTxt
        } else if let cachedTxt {
            Log.d(tag, "DNS fetch failed, using cached data (\(cachedTxt.modified))")
            return cachedTxt
        } else {
            Log.w(tag, "No cached or fresh data available")
            return nil
        }
    }

    private func checkTXTRecordMandatory(nodeCode: String) async throws -> TXTRecordInfo? {
        do {
            let txtCheckURL = DNSTXTClient.buildTXTCheckURL(nodeCode: nodeCode)
            Log.d(tag, "Mandatory TXT record check for: \(txtCheckURL)")

            let selfTag = tag
            let result: String? = try await withTimeoutOrNil(seconds: 30) {
                let response = try await DNSTXTClient.get(txtCheckURL, timeout: 15)
                Log.d(selfTag, "Mandatory check response code: \(response.statusCode)")
                guard response.statusCode == 200 else {
                    throw NSError(domain: "STServiceOrchestrator", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.statusCode)"])
                }
                return response.body
            }

            return result.flatMap { parseTXTResponse($0) }
        } catch {
            Log.e(tag, "Error in mandatory TXT record check", error)
            throw error
        }
    }

    private func checkTXTRecord(nodeCode: String) async -> TXTRecordInfo? {
        do {
            let txtCheckURL = DNSTXTClient.buildTXTCheckURL(nodeCode: nodeCode)
            Log.d(tag, "Checking TXT record for: \(txtCheckURL)")

            let result: String? = (try await withTimeoutOrNil(seconds: 30) { () async throws -> String? in
                let response = try await DNSTXTClient.get(txtCheckURL, timeout: 15)
                return response.statusCode == 200 ? response.body : nil
            }) ?? nil

            return result.flatMap { parseTXTResponse($0) }
        } catch {
            Log.e(tag, "Error checking TXT record", error)
            return nil
        }
    }

    private func parseTXTResponse(_ response: String) -> TXTRecordInfo? {
        do {
            guard let data = response.data(using: .utf8) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = json["Answer"] as? [[String: Any]] else { return nil }

            for answer in answers {
                let type = (answer["type"] as? NSNumber)?.intValue ?? 0
                if type == 16 { // TXT record
                    let txtData = answer["data"] as? String ?? ""
                    return TXTRecordParser.parseTXTData(txtData)
                }
            }
            return nil
        } catch {
            Log.e(tag, "Error parsing TXT response", error)
            return nil
        }
    }
}

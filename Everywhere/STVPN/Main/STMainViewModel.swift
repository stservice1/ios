//
//  STMainViewModel.swift
//  Everywhere
//
//  1:1 port of the Android app's MainActivity.kt business logic (minus the
//  Proxy button, which stays a design-only placeholder per instructions):
//  start/stop, the async link-check-before-start, background ban/expiry
//  monitoring, the 5-tap-logo logout affordance, and logout itself.
//
//  Platform substitution: Android's traffic-threshold validation trigger
//  (`checkTrafficValidationTrigger`, ticking every second while running,
//  firing once >1KiB of traffic is observed) has no iOS equivalent —
//  EverywhereCore (the closed-source mihomo/xray/sing-box engine wrapper)
//  exposes no traffic-total query, unlike Android's Clash core. This
//  triggers the same validation once when the tunnel reports connected +
//  the core running instead of once traffic is observed, which preserves
//  the intent (validate soon after a real connection) without fabricating
//  numbers there's no way to actually measure.
//

import Combine
import Foundation
import NetworkExtension

@MainActor
final class STMainViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStartEnabled = true
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var feedbackShowsProgress = false
    @Published var toastMessage: String?
    @Published private(set) var logoutButtonVisible = false
    @Published var showLogoutConfirm = false

    private let tunnel = TunnelManager.shared
    private let store = ConfigurationStore.shared
    private let orchestrator = STServiceOrchestrator.shared

    private var cancellables = Set<AnyCancellable>()

    // Traffic-validation-trigger substitute state (see the doc comment
    // above) — mirrors Android's `hasTriggeredValidation`.
    private var hasTriggeredValidation = false

    // Logo click counter for the logout button — mirrors MainActivity's
    // `logoClickCount`.
    private var logoClickCount = 0

    private let tag = "MainActivity"

    init() {
        // STVPN only ever drives the mihomo core.
        store.selectedCore = .mihomo

        tunnel.$coreRunning
            .combineLatest(tunnel.$status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (coreRunning, status) in
                guard let self else { return }
                let running = status == .connected && coreRunning
                self.isRunning = running
                if running {
                    self.triggerConnectValidationOnce()
                } else {
                    self.hasTriggeredValidation = false
                }
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        isRunning = tunnel.status == .connected && tunnel.coreRunning
    }

    /// Mirrors MainDesign's logo click listener: 5 taps reveals the logout
    /// button.
    func onLogoTapped() {
        logoClickCount += 1
        if logoClickCount >= 5 {
            logoutButtonVisible = true
        }
    }

    // MARK: - Start / stop

    func toggleStatus() async {
        if isRunning {
            await stopClash()
        } else {
            await startClash()
        }
    }

    private func startClash() async {
        // Clear previous feedback.
        toastMessage = nil
        feedbackMessage = nil

        store.selectedCore = .mihomo

        // Configure the Dynu API key for consumed-status updates.
        orchestrator.setDynuApiKey(BuildSecrets.dynuApiKey)

        // Launch the link check asynchronously FIRST — don't wait for it.
        // This must happen before profile validation so it can fix broken
        // links before the user tries to start.
        Task { [weak self, orchestrator, tag] in
            do {
                Log.d(tag, "Checking for link updates asynchronously...")
                guard let txtInfo = await orchestrator.fetchTXTRecordWithCache(), let vpnUrl = txtInfo.vpnUrl else { return }
                Log.d(tag, "Found link in TXT record, checking if update needed...")
                _ = try await orchestrator.checkAndUpdateLink(
                    newLink: vpnUrl,
                    onProfileUpdateStart: { await MainActor.run { self?.setUpdatingProfile(true) } },
                    onProfileUpdateEnd: { await MainActor.run { self?.setUpdatingProfile(false) } }
                )
            } catch is ProfileUpdateException {
                Log.e(tag, "Failed to rebuild profile after link change")
                await MainActor.run { self?.toastMessage = "Could not update VPN configuration for the new link. Please try again." }
            } catch {
                Log.e(tag, "Error during async link check", error)
            }
        }

        // Check if we have a valid active profile.
        guard let active = store.active, active.imported else {
            toastMessage = "VPN Configuration failed. Please try start again"
            return
        }

        // Reset traffic validation state when starting.
        hasTriggeredValidation = false

        Log.d(tag, "Starting VPN service...")

        // Unlike Android, there's no separate "returns an Intent to launch
        // for consent" leg here — iOS prompts the system VPN-permission
        // sheet itself the first time NETunnelProviderManager saves to
        // preferences, which setEnabled(true:) already triggers.
        await tunnel.setEnabled(true, configuration: active)

        if let error = tunnel.lastError {
            Log.e(tag, "Error during VPN service start: \(error)")
            await tunnel.setEnabled(false, configuration: active)
            toastMessage = error.contains("HTTP") ? "Server error: \(error)" : "Could not start VPN service. Please try again."
            return
        }

        // Start background monitoring for ban/expiration checks.
        orchestrator.startMonitoring()

        Log.d(tag, "VPN service started successfully - validation will occur when the tunnel connects")
    }

    private func stopClash() async {
        await tunnel.setEnabled(false, configuration: store.active)
        // Stop monitoring when the VPN service stops.
        orchestrator.stopMonitoring()
        // Reset traffic validation state when stopping.
        hasTriggeredValidation = false
        Log.d(tag, "Reset traffic validation state")
    }

    private func setUpdatingProfile(_ updating: Bool) {
        isStartEnabled = !updating
        feedbackShowsProgress = updating
        feedbackMessage = updating ? "Updating profile..." : nil
    }

    // MARK: - Connect-triggered validation (traffic-trigger substitute)

    private func triggerConnectValidationOnce() {
        guard !hasTriggeredValidation else { return }
        hasTriggeredValidation = true
        Log.d(tag, "Tunnel connected, triggering validation")
        Task { [weak self] in
            await self?.runConnectTriggeredValidation()
        }
    }

    private func runConnectTriggeredValidation() async {
        toastMessage = "Validating subscription..."

        guard let txtInfo = await orchestrator.fetchTXTRecordWithCache() else {
            Log.w(tag, "Traffic-triggered validation failed to fetch TXT record")
            return
        }

        if txtInfo.banned {
            Log.w(tag, "User is banned - logging out")
            await orchestrator.logout(errorMessage: STServiceOrchestrator.loginErrorBanned)
            return
        }

        if TXTRecordParser.isExpired(txtInfo) {
            Log.w(tag, "User subscription expired - logging out")
            await orchestrator.logout(errorMessage: STServiceOrchestrator.loginErrorExpired)
            return
        }

        // Mark as consumed via the Dynu API (only if not already consumed).
        if !txtInfo.consumed {
            await orchestrator.updateConsumedStatus(txtInfo) { [weak self] message in
                await MainActor.run { self?.toastMessage = message }
            }
            Log.d(tag, "Subscription marked as consumed via traffic-triggered validation")
        }

        Log.d(tag, "Traffic-triggered validation completed successfully")
    }

    // MARK: - Logout

    func logoutRequested() {
        showLogoutConfirm = true
    }

    func confirmLogout() async {
        showLogoutConfirm = false
        await performLogout()
    }

    private func performLogout() async {
        Log.d(tag, "Starting logout process")

        // Stop VPN service if running.
        await tunnel.setEnabled(false, configuration: store.active)

        // Stop monitoring.
        orchestrator.stopMonitoring()

        // Delete all profiles.
        for profile in store.configurations.filter({ $0.coreType == .mihomo }) {
            Log.d(tag, "Deleting profile: \(profile.name)")
            store.delete(profile)
        }

        // Clear any stored credentials/tokens — mirrors Android clearing
        // its (separate, legacy) "LoginPrefs" SharedPreferences.
        UserDefaults(suiteName: "LoginPrefs")?.removePersistentDomain(forName: "LoginPrefs")

        orchestrator.setLoginStatus(false)

        Log.d(tag, "Logout completed, navigating to login")
        orchestrator.redirectToLogin()
    }
}

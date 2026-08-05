//
//  ClashServiceBridge.swift
//  Everywhere
//
//  Mirrors Android's `Context.startClashService()` / `.stopClashService()` /
//  `withClash { ... }` extension functions (util/Clash.kt) — a thin
//  utility layer so STServiceOrchestrator and the STVPN view models don't
//  each reach into TunnelManager/ConfigurationStore directly.
//

import Foundation

enum ClashServiceBridge {
    /// Mirrors `Context.stopClashService()`.
    @MainActor
    static func stopClashService() async {
        await TunnelManager.shared.setEnabled(false, configuration: ConfigurationStore.shared.active)
    }

    /// Mirrors `Context.startClashService()`. Unlike Android, iOS's VPN
    /// permission consent is handled by the system the moment
    /// `NETunnelProviderManager.saveToPreferences()` runs the first time —
    /// there's no separate "returns an Intent to launch for consent" leg to
    /// mirror here; TunnelManager.setEnabled already does the equivalent.
    @MainActor
    static func startClashService() async {
        await TunnelManager.shared.setEnabled(true, configuration: ConfigurationStore.shared.active)
    }

    /// Mirrors `withClash { queryTunnelState() != null }`.
    @MainActor
    static func isServiceRunning() -> Bool {
        TunnelManager.shared.status.isActive
    }
}

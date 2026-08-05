//
//  ProfileFactory.swift
//  Everywhere
//
//  1:1 port of the `withProfile { ... }` block inside LoginActivity.kt's
//  createProfile(nodeCode, subscriptionUrl, ...): wipes any existing STVPN
//  profile, creates a fresh one, retries the subscription fetch up to 3
//  times with 2s/4s backoff, and activates it. Operates only on `.mihomo`
//  configurations — STVPN is a single-engine (mihomo) app, unlike Android's
//  Clash-only Profile store this was ported from, so "all profiles" there
//  maps to "all mihomo configurations" here.
//

import Foundation
import UIKit

enum ProfileFactory {
    /// Thrown when all 3 subscription-fetch attempts fail. `debugInfo` is
    /// the same multi-attempt dump Android showed in a "Connection Failed"
    /// AlertDialog with a "Copy Details" button — callers can surface it
    /// the same way.
    struct DetailedFailure: LocalizedError {
        let debugInfo: String
        let underlying: Error?
        var errorDescription: String? {
            "Failed to fetch subscription: \(underlying?.localizedDescription ?? "unknown error")"
        }
    }

    // Kept as "LoginActivity" (not "ProfileFactory") so log output stays
    // identical to the Kotlin source, which ran this code inline in
    // LoginActivity.
    private static let tag = "LoginActivity"

    private static let debugDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale.current
        return f
    }()

    @MainActor
    static func createProfile(nodeCode: String, subscriptionUrl: String) async throws {
        Log.d(tag, "Creating profile with subscription URL: \(subscriptionUrl)")

        let store = ConfigurationStore.shared

        // Clean up any existing profiles first to prevent conflicts.
        Log.d(tag, "Cleaning up existing profiles...")
        for profile in store.configurations.filter({ $0.coreType == .mihomo }) {
            Log.d(tag, "Deleting existing profile: \(profile.name) (\(profile.id))")
            store.delete(profile)
        }

        Log.d(tag, "Creating new profile...")
        let profileName = "ST VPN Service (\(nodeCode))"
        let cfg = store.create(name: profileName, type: .mihomo, content: "", sourceURL: subscriptionUrl)
        Log.d(tag, "Profile created with UUID: \(cfg.id)")

        guard let url = URL(string: subscriptionUrl) else {
            throw DetailedFailure(debugInfo: "Invalid subscription URL: \(subscriptionUrl)", underlying: URLError(.badURL))
        }

        Log.d(tag, "Setting profile URL and updating...")
        Log.d(tag, "Updating profile to import configuration...")

        // Retry the subscription fetch up to 3 times with increasing delays.
        var updateSuccess = false
        var lastError: Error?
        var errorDetails = ""

        for attempt in 1...3 {
            do {
                Log.d(tag, "Attempt \(attempt): Fetching from \(subscriptionUrl)")
                let content = try await SubscriptionFetcher.fetch(from: url)
                store.update(cfg, content: content)
                updateSuccess = true
                Log.d(tag, "Attempt \(attempt): Success!")
                break
            } catch {
                lastError = error
                let errorMsg = "Attempt \(attempt)/3:\n"
                    + "Error: \(String(describing: type(of: error)))\n"
                    + "Message: \(error.localizedDescription)\n"
                    + "URL: \(subscriptionUrl)\n\n"
                errorDetails += errorMsg
                Log.w(tag, errorMsg)

                if attempt < 3 {
                    let delayMs = attempt * 2000
                    Log.d(tag, "Waiting \(delayMs)ms before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }
            }
        }

        if !updateSuccess {
            let debugInfo = """
            Subscription fetch failed after 3 attempts

            === Debug Information ===
            \(errorDetails)=== System Info ===
            iOS: \(UIDevice.current.systemVersion)
            Device: \(UIDevice.current.model)
            Time: \(debugDateFormatter.string(from: Date()))
            """

            Log.e(tag, debugInfo)
            throw DetailedFailure(debugInfo: debugInfo, underlying: lastError)
        }

        // Wait a moment for the update to complete.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        guard let profile = store.configurations.first(where: { $0.id == cfg.id }) else {
            throw DetailedFailure(debugInfo: "Failed to create a profile", underlying: nil)
        }

        // Set the profile as active.
        if profile.imported {
            Log.d(tag, "Setting profile as active")
            store.setActive(profile)
        } else {
            Log.w(tag, "Profile not imported, cannot set as active")
        }
    }
}

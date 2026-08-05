//
//  STRootView.swift
//  Everywhere
//
//  Entry point: switches between LoginView and STMainView. The initial
//  choice mirrors Android's LauncherActivity (routes to Main if any
//  profile exists, else Login) composed with MainActivity.main()'s own
//  immediate isLoggedIn() double-check (which would otherwise just bounce
//  straight back to Login on the next frame) — so login flag and profile
//  existence both have to hold for STVPN to open on Main.
//
//  STServiceOrchestrator.logout(...) (ban / expiration / manual logout)
//  posts `.stvpnRedirectToLogin`, observed here to switch back to
//  LoginView — mirrors Android's `redirectToLogin` relaunching
//  LoginActivity with CLEAR_TASK.
//

import SwiftUI

struct STRootView: View {
    @State private var isLoggedIn: Bool

    init() {
        _isLoggedIn = State(initialValue: Self.computeInitialLoginState())
    }

    var body: some View {
        Group {
            if isLoggedIn {
                STMainView()
            } else {
                LoginView(onLogin: { isLoggedIn = true })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stvpnRedirectToLogin)) { _ in
            isLoggedIn = false
        }
    }

    private static func computeInitialLoginState() -> Bool {
        Log.d("LauncherActivity", "Checking for existing profiles...")
        let hasProfiles = ConfigurationStore.shared.configurations.contains { $0.coreType == .mihomo }
        guard hasProfiles else {
            Log.d("LauncherActivity", "No profiles found, launching LoginActivity")
            return false
        }
        Log.d("LauncherActivity", "Profile found, launching MainActivity")
        return STServiceOrchestrator.shared.isLoggedIn()
    }
}

#Preview {
    STRootView()
}

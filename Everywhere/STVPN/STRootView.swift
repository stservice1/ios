//
//  STRootView.swift
//  Everywhere
//
//  Design-pass entry point: switches between LoginView and STMainView.
//  `isLoggedIn` is local, in-memory state — there's no session/auth
//  logic yet, just the navigation this screen pair needs to be demoable.
//  A real auth flow (validating the node code, persisting the session)
//  will replace this switch later.
//

import SwiftUI

struct STRootView: View {
    @State private var isLoggedIn = false

    var body: some View {
        if isLoggedIn {
            STMainView()
        } else {
            LoginView(onLogin: { isLoggedIn = true })
        }
    }
}

#Preview {
    STRootView()
}

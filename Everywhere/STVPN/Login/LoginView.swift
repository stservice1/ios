//
//  LoginView.swift
//  Everywhere
//
//  Ported from the Android app's activity_login.xml: logo + title, a node
//  code field, and a login button, all sitting in the upper third of the
//  screen on a pure black background.
//
//  Design only for now — no validation, network calls, or cooldown/error
//  states are wired up yet (the Android layout also has an error banner,
//  a progress spinner, and a cooldown overlay on the button; those are
//  logic-driven and will come with the real login flow later). Tapping
//  "Log in" just calls `onLogin`.
//

import SwiftUI

struct LoginView: View {
    @State private var nodeCode: String = ""
    @FocusState private var fieldFocused: Bool

    /// Called when the login button is tapped. No validation happens here
    /// yet — this is purely a navigation hook for the design pass.
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Android's weightSum=3 LinearLayout (weight 1 above the
                // content, weight 2 below) keeps the form in the upper
                // third of the screen. A fixed-height top spacer plus a
                // flexible bottom Spacer reproduces that without needing
                // exact weighted-layout math.
                Spacer()
                    .frame(height: geo.size.height / 3)

                VStack(spacing: 24) {
                    header
                    nodeCodeField
                    loginButton
                }

                Spacer()
            }
            .padding(.horizontal, STMetrics.loginHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(STColor.loginBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image("STVPNLogo")
                .resizable()
                .scaledToFit()
                .frame(width: STMetrics.logoSize, height: STMetrics.logoSize)

            Text("ST VPN Service")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(STColor.brandGreen)
        }
    }

    private var nodeCodeField: some View {
        TextField("", text: $nodeCode)
            .focused($fieldFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(STColor.textPrimary)
            .accessibilityIdentifier("loginNodeCodeField")
            .padding(16)
            .background(STColor.loginFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(STColor.loginAccent, lineWidth: fieldFocused ? 2 : 1)
            )
            .overlay(alignment: .leading) {
                // Emulates Material's outlined-box floating hint: sits inline
                // when empty, matches the field's accent color always (the
                // Android layout never shrinks it to a top-aligned label
                // outside the box, so a plain placeholder is a faithful port).
                if nodeCode.isEmpty {
                    Text("Enter Node Code")
                        .foregroundStyle(STColor.loginFieldHint)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    private var loginButton: some View {
        Button(action: onLogin) {
            Text("Log in")
                .font(.system(size: 16))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(STColor.loginAccent)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("loginButton")
    }
}

#Preview {
    LoginView(onLogin: {})
}

//
//  LoginView.swift
//  Everywhere
//
//  Ported from the Android app's activity_login.xml: logo + title, a node
//  code field, and a login button, all sitting in the upper third of the
//  screen on a pure black background. Business logic (validation, cooldown,
//  profile creation) lives in LoginViewModel — this view only binds to it.
//

import SwiftUI
import UIKit

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @FocusState private var fieldFocused: Bool

    /// Called once LoginViewModel.login() reports success — switches the
    /// app to STMainView. No further validation happens here.
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
                    errorBanner
                    loginArea
                }

                Spacer()
            }
            .padding(.horizontal, STMetrics.loginHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(STColor.loginBackground.ignoresSafeArea())
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .alert("Connection Failed", isPresented: debugAlertBinding, presenting: viewModel.debugDetails) { details in
            Button("Copy Details") {
                UIPasteboard.general.string = details
            }
            Button("Close", role: .cancel) { viewModel.debugDetails = nil }
        } message: { details in
            Text(details)
        }
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
        TextField("", text: $viewModel.nodeCode)
            .focused($fieldFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
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
                if viewModel.nodeCode.isEmpty {
                    Text("Enter Node Code")
                        .foregroundStyle(STColor.loginFieldHint)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(STColor.loginError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(STColor.loginErrorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    /// Button, progress spinner, and cooldown countdown all occupy the same
    /// slot so the layout doesn't jump between states — mirrors Android
    /// hiding the button with `View.INVISIBLE` (space kept) rather than
    /// `View.GONE`.
    private var loginArea: some View {
        ZStack {
            loginButton
                .opacity(viewModel.loginButtonVisible ? 1 : 0)
                .disabled(!viewModel.loginButtonVisible)

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if let cooldownText = viewModel.cooldownText {
                Text(cooldownText)
                    .font(.system(size: 14))
                    .foregroundStyle(STColor.textSecondary)
            }
        }
    }

    private var loginButton: some View {
        Button {
            Task {
                let success = await viewModel.login()
                if success { onLogin() }
            }
        } label: {
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

    private var debugAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.debugDetails != nil },
            set: { if !$0 { viewModel.debugDetails = nil } }
        )
    }
}

#Preview {
    LoginView(onLogin: {})
}

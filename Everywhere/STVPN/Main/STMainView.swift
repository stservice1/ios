//
//  STMainView.swift
//  Everywhere
//
//  Ported from the Android app's design_main.xml: a header (logo, title,
//  version), a start/stop status card, and a Proxy card that only appears
//  while "running". Of design_main.xml's full card/label list (Profile,
//  Providers, Logs, Settings, Help, About) only the two the design asked
//  for are ported — the rest were `visibility="gone"` in the Android
//  layout too, so nothing is actually missing from what's shown today.
//
//  Business logic (start/stop, monitoring, logout) lives in
//  STMainViewModel — this view only binds to it. The Proxy card's tap
//  action is intentionally left a no-op (per instructions: everything
//  except the Proxy button's own dashboard logic).
//

import SwiftUI

struct STMainView: View {
    @StateObject private var viewModel = STMainViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                if let feedback = viewModel.feedbackMessage {
                    feedbackPanel(feedback)
                }

                VStack(spacing: STMetrics.cardMarginVertical * 2) {
                    statusCard
                    if viewModel.isRunning {
                        proxyCard
                    }
                }
                .padding(.vertical, STMetrics.cardMarginVertical)

                if viewModel.logoutButtonVisible {
                    logoutButton
                }
            }
            .padding(.horizontal, STMetrics.mainHorizontalPadding)
        }
        .accessibilityIdentifier("stMainView")
        .background(STColor.background.ignoresSafeArea())
        .animation(.default, value: viewModel.isRunning)
        .onAppear { viewModel.onAppear() }
        .alert("Notice", isPresented: toastBinding, presenting: viewModel.toastMessage) { _ in
            Button("OK", role: .cancel) { viewModel.toastMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Logout Warning", isPresented: $viewModel.showLogoutConfirm) {
            Button("Yes, Logout", role: .destructive) {
                Task { await viewModel.confirmLogout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Logging out will permanently delete your profile and all VPN configurations. You will need a new activation code to use this service again.\n\nAre you sure you want to proceed?")
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Image("STVPNLogo")
                .resizable()
                .scaledToFit()
                .frame(width: STMetrics.logoSize, height: STMetrics.logoSize)
                .frame(width: STMetrics.logoContainerSize, height: STMetrics.logoContainerSize)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.onLogoTapped() }

            Text("ST VPN Service")
                .font(.title3.weight(.semibold))
                .foregroundStyle(STColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(STColor.textSecondary)
        }
        .frame(minHeight: STMetrics.topBannerHeight)
    }

    private var statusCard: some View {
        LargeActionCard(
            systemImage: viewModel.isRunning ? "checkmark.circle" : "nosign",
            title: viewModel.isRunning ? "Running" : "Stopped",
            subtitle: viewModel.isRunning ? "Tap to stop" : "Tap to start",
            backgroundColor: viewModel.isRunning ? STColor.brandGreen : STColor.surface,
            isEnabled: viewModel.isStartEnabled,
            action: { Task { await viewModel.toggleStatus() } }
        )
        .accessibilityIdentifier("statusCard")
    }

    private var proxyCard: some View {
        LargeActionCard(
            systemImage: "square.grid.3x3.fill",
            title: "Proxy",
            subtitle: "Rule Mode",
            backgroundColor: STColor.surface,
            action: {}
        )
        .accessibilityIdentifier("proxyCard")
        .transition(.opacity)
    }

    private func feedbackPanel(_ message: String) -> some View {
        HStack(spacing: 12) {
            if viewModel.feedbackShowsProgress {
                ProgressView()
            }
            Text(message)
                .foregroundStyle(STColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(STColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: STMetrics.cardCornerRadius))
        .padding(.top, STMetrics.cardMarginVertical)
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            viewModel.logoutRequested()
        } label: {
            Text("Logout")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        }
        .padding(.vertical, STMetrics.cardMarginVertical * 2)
    }

    private var versionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "v\(short)"
    }

    private var toastBinding: Binding<Bool> {
        Binding(
            get: { viewModel.toastMessage != nil },
            set: { if !$0 { viewModel.toastMessage = nil } }
        )
    }
}

#Preview {
    STMainView()
}

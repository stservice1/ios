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
//  Design only for now: `isRunning` is local, in-memory UI state toggled
//  by tapping the status card, purely so both card states (and the Proxy
//  card's appearance) are visible/demoable. No tunnel is started or
//  stopped — that plugs in later where `onToggleRunning` is called.
//

import SwiftUI

struct STMainView: View {
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                VStack(spacing: STMetrics.cardMarginVertical * 2) {
                    statusCard
                    if isRunning {
                        proxyCard
                    }
                }
                .padding(.vertical, STMetrics.cardMarginVertical)
            }
            .padding(.horizontal, STMetrics.mainHorizontalPadding)
        }
        .accessibilityIdentifier("stMainView")
        .background(STColor.background.ignoresSafeArea())
        .animation(.default, value: isRunning)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Image("STVPNLogo")
                .resizable()
                .scaledToFit()
                .frame(width: STMetrics.logoSize, height: STMetrics.logoSize)
                .frame(width: STMetrics.logoContainerSize, height: STMetrics.logoContainerSize)

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
            systemImage: isRunning ? "checkmark.circle" : "nosign",
            title: isRunning ? "Running" : "Stopped",
            subtitle: isRunning ? "0 B Forwarded" : "Tap to start",
            backgroundColor: isRunning ? STColor.brandGreen : STColor.surface,
            action: { isRunning.toggle() }
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

    private var versionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "v\(short)"
    }
}

#Preview {
    STMainView()
}

//
//  LargeActionCard.swift
//  Everywhere
//
//  Ported from the Android app's `LargeActionCard` custom view
//  (design/src/main/java/.../view/LargeActionCard.kt) + its layout,
//  component_large_action_label.xml: a tappable Material card with a
//  leading icon and a title/subtitle text column.
//
//  Used for both the start/stop status card and the Proxy card on the
//  main screen — same component, different icon/text/color/action, exactly
//  as in the Android source (`design_main.xml` reuses the same view tag).
//

import SwiftUI

struct LargeActionCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var backgroundColor: Color = STColor.surface
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    Image(systemName: systemImage)
                        .font(.system(size: STMetrics.cardIconSize))
                        .foregroundStyle(STColor.textPrimary)
                }
                .frame(width: STMetrics.logoContainerSize, height: STMetrics.logoContainerSize)

                VStack(alignment: .leading, spacing: STMetrics.cardTextSpacing) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(STColor.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(STColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, STMetrics.cardTrailingMargin)
            }
            .padding(.vertical, STMetrics.cardContentPaddingVertical)
            .frame(minHeight: STMetrics.cardMinHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: STMetrics.cardCornerRadius)
                    .fill(backgroundColor)
            )
            .shadow(color: .black.opacity(0.35), radius: STMetrics.cardElevation, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

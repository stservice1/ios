//
//  STMetrics.swift
//  Everywhere
//
//  Spacing/sizing tokens ported 1:1 (dp -> pt) from the Android app's
//  design/src/main/res/values/dimens.xml. Keep in sync with that file.
//

import CoreGraphics

enum STMetrics {
    /// `main_padding_horizontal` — horizontal screen padding on the main screen.
    static let mainHorizontalPadding: CGFloat = 30

    /// Login screen's explicit `paddingStart`/`paddingEnd`.
    static let loginHorizontalPadding: CGFloat = 32

    /// `main_top_banner_height` — min height of the logo/title header row.
    static let topBannerHeight: CGFloat = 90

    /// `main_logo_size` — the logo image itself.
    static let logoSize: CGFloat = 50

    /// `large_item_header_layout_size` — the square frame the logo sits in.
    static let logoContainerSize: CGFloat = 70

    /// `main_card_margin_vertical` — each `LargeActionCard`'s vertical margin
    /// (applied above *and* below, so cards end up ~10pt apart).
    static let cardMarginVertical: CGFloat = 5

    /// `large_action_card_radius`.
    static let cardCornerRadius: CGFloat = 8

    /// `large_action_card_min_height`.
    static let cardMinHeight: CGFloat = 85

    /// `large_action_card_elevation` — used as a soft drop-shadow radius.
    static let cardElevation: CGFloat = 5

    /// `large_item_padding_vertical` — inside a card, above/below the icon+text row.
    static let cardContentPaddingVertical: CGFloat = 15

    /// `large_item_header_component_size` — the icon glyph itself.
    static let cardIconSize: CGFloat = 30

    /// `large_item_header_margin_horizontal` — margin on both sides of the icon.
    static let cardIconMarginHorizontal: CGFloat = 20

    /// `large_item_tailing_margin_horizontal` — margin after the text column.
    static let cardTrailingMargin: CGFloat = 20

    /// `large_item_text_margin` — gap between a card's title and subtitle.
    static let cardTextSpacing: CGFloat = 5
}

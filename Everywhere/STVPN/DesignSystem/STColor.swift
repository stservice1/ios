//
//  STColor.swift
//  Everywhere
//
//  Design tokens ported 1:1 from the Android app's
//  design/src/main/res/values/colors.xml + themes.xml (AppThemeDark).
//  Keep these in sync with that file if the Android palette changes.
//

import SwiftUI

extension Color {
    /// `0xRRGGBB`, e.g. `Color(hex: 0x6b8069)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Colors ported from the Android app's dark theme (`AppThemeDark`), the only
/// theme this app targets — the Android app also has a light theme, but both
/// reference screens (login, main) are dark-only in the source screenshots.
enum STColor {
    /// `color_clash_dark` — running-state card background; also the login
    /// screen's title text color.
    static let brandGreen = Color(hex: 0x6b8069)

    /// `color_dark_background` — screen background.
    static let background = Color(hex: 0x121212)

    /// Login screen forces pure black (`android:background="#000000"`)
    /// rather than the theme's `color_dark_background`.
    static let loginBackground = Color.black

    /// `color_dark_surface` — stopped-state card background, and the
    /// default `MaterialCardView` surface color used by the Proxy card.
    static let surface = Color(hex: 0x202020)

    /// `color_dark_control_disabled`.
    static let controlDisabled = Color(hex: 0x808080)

    /// Login screen's outlined text field: hint/label text.
    static let loginFieldHint = Color(hex: 0x90CAF9)

    /// Login screen's outlined text field: box stroke, and the login button.
    static let loginAccent = Color(hex: 0x2196F3)

    /// Login screen's outlined text field: box background.
    static let loginFieldBackground = Color(hex: 0x1A1A1A)

    /// Login screen's error banner text (`#F44336`, Material Red 500).
    static let loginError = Color(hex: 0xF44336)

    /// Login screen's error banner background.
    static let loginErrorBackground = Color(hex: 0x1A0000)

    /// High-emphasis on-surface text (card titles).
    static let textPrimary = Color.white

    /// Medium-emphasis on-surface text (card subtitles, version label) —
    /// Material's dark-theme "medium emphasis" is ~60% white.
    static let textSecondary = Color.white.opacity(0.6)
}

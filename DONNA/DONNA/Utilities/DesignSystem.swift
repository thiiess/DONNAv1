import SwiftUI

// MARK: - Themes

/// User-selectable colour themes (Einstellungen → Erscheinungsbild). DONNA runs in dark
/// mode; each theme tints the surfaces slightly towards its accent so the app reads as
/// one warm, calm space instead of stock system grey.
enum DONNATheme: String, CaseIterable, Identifiable {
    case bernstein, salbei, ozean, lavendel, koralle, graphit

    static let storageKey = "donna_theme"
    static let `default`: DONNATheme = .bernstein

    /// Read on every access, so views pick up a change on their next render. The app
    /// root re-creates the view tree when the stored theme changes (see DONNAApp).
    static var current: DONNATheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DONNATheme.init(rawValue:)) ?? .default
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bernstein: return "Bernstein"
        case .salbei:    return "Salbei"
        case .ozean:     return "Ozean"
        case .lavendel:  return "Lavendel"
        case .koralle:   return "Koralle"
        case .graphit:   return "Graphit"
        }
    }

    /// (accent, background, surface, elevated, bubble)
    private var palette: (String, String, String, String, String) {
        switch self {
        case .bernstein: return ("#E8A06A", "#16120F", "#211B17", "#2B231E", "#2E241F")
        case .salbei:    return ("#94C4A0", "#111512", "#1A201C", "#222A25", "#1F2B23")
        case .ozean:     return ("#74B6D6", "#101419", "#182029", "#202A34", "#1A2834")
        case .lavendel:  return ("#BBA6E6", "#14121D", "#1E1B29", "#272334", "#262137")
        case .koralle:   return ("#F0907F", "#171111", "#231A19", "#2D2220", "#33211F")
        case .graphit:   return ("#D9D4CC", "#111111", "#1B1B1B", "#252525", "#292929")
        }
    }

    var accent: Color     { Color(hex: palette.0) }
    var background: Color { Color(hex: palette.1) }
    var surface: Color    { Color(hex: palette.2) }
    var elevated: Color   { Color(hex: palette.3) }
    var bubble: Color     { Color(hex: palette.4) }
}

// MARK: - Design System

enum DS {

    // MARK: Colors

    enum Colors {
        // Surfaces follow the selected theme (see DONNATheme).
        static var backgroundPrimary: Color   { DONNATheme.current.background }
        static var backgroundSecondary: Color { DONNATheme.current.surface }
        static var backgroundTertiary: Color  { DONNATheme.current.elevated }
        /// Legacy alias from V1 (was the blue AccentColor asset). Points at the warm
        /// brand accent so older views (onboarding, routine status) match the rest of the app.
        static var accent: Color { warmAccent }
        static let textPrimary          = Color("TextPrimary")
        static let textSecondary        = Color("TextSecondary")
        static let textTertiary         = Color("TextTertiary")
        static let destructive          = Color("Destructive")
        static let success              = Color("Success")
        static let separator            = Color("LineSeparator")

        // Brand palette — the accent follows the selected theme. The name `warmAccent`
        // stays for compatibility; it is "the accent", whatever the theme.
        static var warmAccent: Color { DONNATheme.current.accent }
        /// Text/icons on an accent-filled background (dark — the accents are light tones).
        static let onAccent       = Color(hex: "#15110E")
        static let warmLight      = Color(hex: "#F5E6D8")
        static let warmDark       = Color(hex: "#6B3410")
        static let darkBackground = Color(hex: "#2A2420")
        static let darkSurface    = Color(hex: "#E8A06A")

        static var appBackground: Color { DONNATheme.current.background }

        static var donnaBubbleBg: Color { DONNATheme.current.bubble }
        static var donnaBubbleFg: Color { DONNATheme.current.accent }

        static func category(_ cat: RoutineCategory) -> Color {
            switch cat {
            case .sleep:     return Color(hex: "#5E5CE6")
            case .sport:     return Color(hex: "#FF6B35")
            case .learning:  return Color(hex: "#5AA9E6")
            case .skincare:  return Color(hex: "#BF5AF2")
            case .nutrition: return Color(hex: "#30D158")
            case .custom:    return Color("TextTertiary")
            }
        }

        static func priority(_ p: Priority) -> Color {
            switch p {
            case .high:   return DS.Colors.destructive
            case .medium: return Color(hex: "#FF9F0A")
            case .low:    return DS.Colors.success
            case .none:   return DS.Colors.textSecondary
            }
        }
    }

    // MARK: Typography

    /// Headings use a serif — DONNA's own handwriting, closer to a paper planner than to
    /// a stock settings screen. Body text stays sans for legibility.
    enum Typography {
        static let title:      Font = .system(.largeTitle, design: .serif).weight(.semibold)
        static let heading:    Font = .system(.title2, design: .serif).weight(.semibold)
        static let subheading: Font = .system(.headline, design: .serif).weight(.medium)
        static let body:       Font = .body.weight(.regular)
        static let caption:    Font = .caption.weight(.regular)
    }

    // MARK: Spacing

    enum Spacing {
        static let horizontal: CGFloat = 16
        static let vertical:   CGFloat = 12
        static let section:    CGFloat = 24
    }

    // MARK: Corner Radius

    enum Radius {
        static let card:   CGFloat = 14
        static let chip:   CGFloat = 8
        static let button: CGFloat = 999
    }

    // MARK: Animation

    static let animation = Animation.easeInOut(duration: 0.2)
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Adaptive color

extension Color {
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        }))
        #endif
    }
}

// MARK: - View helpers

extension View {
    func dsCard() -> some View {
        self
            .background(DS.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    func dsHorizontalPadding() -> some View {
        self.padding(.horizontal, DS.Spacing.horizontal)
    }
}

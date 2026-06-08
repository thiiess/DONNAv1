import SwiftUI

// MARK: - Design System

enum DS {

    // MARK: Colors

    enum Colors {
        static let backgroundPrimary    = Color("BackgroundPrimary")
        static let backgroundSecondary  = Color("BackgroundSecondary")
        static let backgroundTertiary   = Color("BackgroundTertiary")
        static let accent               = Color("AccentColor")
        static let textPrimary          = Color("TextPrimary")
        static let textSecondary        = Color("TextSecondary")
        static let textTertiary         = Color("TextTertiary")
        static let destructive          = Color("Destructive")
        static let success              = Color("Success")
        static let separator            = Color("LineSeparator")

        // Warm brand palette
        static let warmAccent     = Color(light: Color(hex: "#C4783C"), dark: Color(hex: "#E8A06A"))
        static let warmLight      = Color(hex: "#F5E6D8")
        static let warmDark       = Color(hex: "#6B3410")
        static let darkBackground = Color(hex: "#2A2420")
        static let darkSurface    = Color(hex: "#E8A06A")

        static func category(_ cat: RoutineCategory) -> Color {
            switch cat {
            case .sleep:     return Color(hex: "#5E5CE6")
            case .sport:     return Color(hex: "#FF6B35")
            case .learning:  return Color("AccentColor")
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

    enum Typography {
        static let title:      Font = .largeTitle.weight(.semibold)
        static let heading:    Font = .title2.weight(.semibold)
        static let subheading: Font = .headline.weight(.medium)
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
        static let card:   CGFloat = 12
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

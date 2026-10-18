import SwiftUI

// MARK: - Palette
/// Brand colors. Adaptive values (light/dark) live in Assets.xcassets as `DS*` color sets.
/// Signature duo: electric violet (`brand`) + hot coral (`brandSecondary`).

enum Palette {
    // Brand
    static let brand: Color = Color("DSBrand")
    static let brandSecondary: Color = Color("DSBrandSecondary")

    /// Diagonal violet → coral. Use for hero fills and primary buttons.
    static let brandGradient: LinearGradient = LinearGradient(
        colors: [Color("DSBrand"), Color("DSBrandSecondary")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Horizontal violet → coral, for progress bars and thin strokes.
    static let brandGradientHorizontal: LinearGradient = LinearGradient(
        colors: [Color("DSBrand"), Color("DSBrandSecondary")],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Surfaces & text
    /// App background: warm off-white (light) / deep ink (dark).
    static let canvas: Color = Color("DSCanvas")
    /// Card fill.
    static let surface: Color = Color("DSSurface")
    /// Primary text.
    static let ink: Color = Color("DSInk")
    /// Secondary text (≥ 4.5:1 on canvas in both appearances).
    static let inkSecondary: Color = Color("DSInkSecondary")
    /// Hairlines and subtle fills.
    static let hairline: Color = Color("DSInkSecondary").opacity(0.18)

    // Semantic
    static let keep: Color = Color("DSKeep")
    static let toss: Color = Color("DSToss")
    static let warning: Color = Color("DSWarning")
    static let info: Color = Color("DSInfo")

    /// Text/icon color to use on top of `brandGradient`, `keep`, `toss` fills.
    static let onBrand: Color = .white
}

// MARK: - Fixed (non-adaptive) hues

/// Builds an sRGB color from a 0xRRGGBB literal. File-private to avoid clashing with other `init(hex:)` helpers.
fileprivate func dsRGB(_ hex: UInt32) -> Color {
    let red: Double = Double((hex >> 16) & 0xFF) / 255.0
    let green: Double = Double((hex >> 8) & 0xFF) / 255.0
    let blue: Double = Double(hex & 0xFF) / 255.0
    return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
}

// MARK: - Category Group Colors
/// 14 distinct vivid hues spread around the color wheel so stacks are colorful but organized.
/// Used as tints/fills (not as body-text color on canvas).

extension CategoryGroup {
    private var hexPair: (UInt32, UInt32) {
        switch self {
        case .eventsPlanning:      return (0xFF4757, 0xFF7A59) // red
        case .homeLiving:          return (0xFF7A45, 0xFFA552) // coral
        case .foodDrink:           return (0xFFA41B, 0xFFC93C) // orange
        case .information:         return (0xF2C200, 0xFFE066) // yellow
        case .other:               return (0x9BC53D, 0xC3E26B) // lime
        case .lifestyleWellness:   return (0x2DC46B, 0x6EE7A0) // green
        case .placesTravel:        return (0x11B5A4, 0x3DD9C1) // teal
        case .system:              return (0x15B2D3, 0x5ED3F3) // cyan
        case .communication:       return (0x2F8CFF, 0x5CB8FF) // blue
        case .workProductivity:    return (0x3B4FD8, 0x6577F3) // cobalt
        case .productsTech:        return (0x6E56FF, 0x9B8CFF) // indigo
        case .mediaEntertainment:  return (0xA64DFF, 0xCB8CFF) // violet
        case .clothingAccessories: return (0xE040C8, 0xF57BDF) // magenta
        case .socialMedia:         return (0xFF3D8B, 0xFF7AAE) // pink
        }
    }

    var color: Color {
        dsRGB(hexPair.0)
    }

    var gradient: LinearGradient {
        let pair: (UInt32, UInt32) = hexPair
        return LinearGradient(
            colors: [dsRGB(pair.0), dsRGB(pair.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Short, friendly label for tight spaces (chips, onboarding demo).
    var chipName: String {
        switch self {
        case .socialMedia: return "Social"
        case .communication: return "Chats"
        case .clothingAccessories: return "Style"
        case .productsTech: return "Tech"
        case .homeLiving: return "Home"
        case .foodDrink: return "Food"
        case .placesTravel: return "Places"
        case .eventsPlanning: return "Plans"
        case .workProductivity: return "Work"
        case .mediaEntertainment: return "Media"
        case .lifestyleWellness: return "Life"
        case .information: return "Info"
        case .system: return "System"
        case .other: return "Other"
        }
    }
}

extension ScreenshotCategory {
    var color: Color { group.color }
    var gradient: LinearGradient { group.gradient }
}

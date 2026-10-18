import CoreGraphics

// MARK: - Spacing
/// 4-pt based spacing scale. Be generous.

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Standard horizontal screen gutter.
    static let gutter: CGFloat = 20
}

// MARK: - Corner Radius
/// Chunky radii. Pair with `.rect(cornerRadius:)` / `RoundedRectangle(cornerRadius:style: .continuous)`.

enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

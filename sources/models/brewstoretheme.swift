import AppKit
import SwiftUI

enum Spacing {
    /// 2pt micro-gap (badge icons, line-height micro-compensation)
    static let xxs: CGFloat = 2
    /// 4pt tight gap (status chips, inline elements)
    static let xs: CGFloat = 4
    /// 8pt element-to-element within rows
    static let sm: CGFloat = 8
    /// 12pt standard row-to-row and compact card spacing
    static let md: CGFloat = 12
    /// 16pt card inner padding, section headers
    static let lg: CGFloat = 16
    /// 20pt standard desktop margin, major block padding
    static let xl: CGFloat = 20
    /// 28pt major section dividers and dashboard hero gaps
    static let xxl: CGFloat = 28
}

enum Radius {
    /// 4pt for small keyboard tags and code badges
    static let mini: CGFloat = 4
    static let xs: CGFloat = 4
    /// 6pt for capsule-adjacent status chips and button pills
    static let pill: CGFloat = 6
    /// 8pt for disclosure groups, search bars, and compact cells
    static let small: CGFloat = 8
    static let sm: CGFloat = 8
    /// 10pt for standard cards, list rows, and grid items
    static let card: CGFloat = 10
    static let md: CGFloat = 10
    /// 14pt for modals, sheets, and floating windows
    static let panel: CGFloat = 14
    static let lg: CGFloat = 14
    /// 16pt for major hero banners and full-screen cards
    static let modal: CGFloat = 16
    static let xl: CGFloat = 16
}

enum BrewCardElevation: Sendable {
    case flat
    case subtle
    case elevated
}

struct BrewCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.md
    var radius: CGFloat = Radius.card
    var isSelected: Bool = false
    var elevation: BrewCardElevation = .subtle

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .shadow(
                color: elevation == .elevated ? Color.black.opacity(0.12) : Color.clear,
                radius: elevation == .elevated ? 8 : 0,
                y: elevation == .elevated ? 3 : 0
            )
    }

    private var backgroundStyle: some ShapeStyle {
        switch elevation {
        case .flat:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        case .subtle:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        case .elevated:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var strokeColor: Color {
        if isSelected {
            return Color.accentColor
        }
        return Color.primary.opacity(0.08)
    }
}

extension View {
    func brewCardStyle(
        elevation: BrewCardElevation = .subtle,
        padding: CGFloat = Spacing.md,
        radius: CGFloat = Radius.card,
        isSelected: Bool = false
    ) -> some View {
        modifier(BrewCardModifier(padding: padding, radius: radius, isSelected: isSelected, elevation: elevation))
    }

    func brewCardStyle(
        padding: CGFloat,
        radius: CGFloat = Radius.card,
        isSelected: Bool = false,
        elevation: BrewCardElevation = .subtle
    ) -> some View {
        modifier(BrewCardModifier(padding: padding, radius: radius, isSelected: isSelected, elevation: elevation))
    }

    func brewPillStyle(
        horizontalPadding: CGFloat = Spacing.sm,
        verticalPadding: CGFloat = Spacing.xxs,
        tint: Color = .secondary
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

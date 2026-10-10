import SwiftUI

/// Design System — dark-only, asset-backed colors, semantic SF Pro.
/// Never use Color.white / Color.black / RGB literals in views.
enum DS {
    enum Color {
        static let background = SwiftUI.Color("Background")       // #0A0C0F
        static let surface = SwiftUI.Color("Surface")             // #12161B
        static let raised = SwiftUI.Color("Raised")               // #1A2027
        static let hairline = SwiftUI.Color("Hairline")           // white 8%
        static let scrim = SwiftUI.Color("Scrim")                 // black 25%
        static let labelPrimary = SwiftUI.Color("LabelPrimary")   // #F2F4F7
        static let labelSecondary = SwiftUI.Color("LabelSecondary") // #8E99A5
        static let labelTertiary = SwiftUI.Color("LabelTertiary") // #5C6672
        static let accent = SwiftUI.Color.accentColor
    }

    enum Font {
        static let display = SwiftUI.Font.largeTitle.weight(.semibold)
        static let title = SwiftUI.Font.title2.weight(.semibold)
        static let headline = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let label = SwiftUI.Font.subheadline.weight(.medium)
        static let caption = SwiftUI.Font.footnote
        static let number = SwiftUI.Font.title.weight(.semibold).monospacedDigit()
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 10
        static let row: CGFloat = 16
        static let sheet: CGFloat = 24
    }
}

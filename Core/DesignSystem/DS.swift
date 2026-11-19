import SwiftUI
import UIKit

enum DS {
    enum Color {
        static let background = SwiftUI.Color(uiColor: .systemGroupedBackground)
        static let surface = SwiftUI.Color(uiColor: .secondarySystemGroupedBackground)
        static let raised = SwiftUI.Color(uiColor: .tertiarySystemGroupedBackground)
        static let labelPrimary = SwiftUI.Color.primary
        static let labelSecondary = SwiftUI.Color.secondary
        static let labelTertiary = SwiftUI.Color.secondary
        static let accent = SwiftUI.Color("AccentColor")
    }

    enum Font {
        static let display = SwiftUI.Font.largeTitle.weight(.bold)
        static let title = SwiftUI.Font.title2.weight(.semibold)
        static let headline = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let label = SwiftUI.Font.subheadline.weight(.medium)
        static let caption = SwiftUI.Font.footnote
        static let number = SwiftUI.Font.title3.weight(.semibold).monospacedDigit()
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
        static let control: CGFloat = 12
        static let row: CGFloat = 18
    }
}

struct TeamIdentity: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 52, height: 52)
                .background(DS.Color.accent.opacity(0.12), in: .rect(cornerRadius: DS.Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Wild Circuits").font(.headline)
                Text("FTC #36611").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusLabel: View {
    let title: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct DataNotice: View {
    let title: String
    let detail: String
    let icon: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Label(title, systemImage: icon).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            if let retry {
                Button("Retry", action: retry).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

struct FormSaveError: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

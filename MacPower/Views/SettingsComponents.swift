import AppKit
import SwiftUI

// Building blocks shared by the settings pages, sized like macOS System
// Settings: 13pt row text, 11pt secondary captions, 10pt corner cards.

/// A row title with an optional plain-language explanation beneath it.
struct SettingsRowLabel: View {
    var title: LocalizedStringKey
    var caption: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The preview at the top of a page: a short caption over the live content on a raised card.
struct SettingsPreviewCard<Content: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .padding(.vertical, 4)
    }
}

/// One option drawn as a picture of its result, with its name beneath. The
/// selected card gets the accent ring, like the choices in System Settings' Appearance.
struct SettingsChoiceCard<Thumbnail: View>: View {
    var title: LocalizedStringKey
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var thumbnail: Thumbnail
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                thumbnail
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(8)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Color.primary.opacity(0.04)))
            .overlay {
                shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// This app's own icon, exactly as Finder and the Dock show it.
struct SettingsAppIcon: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small colored tile holding a white SF Symbol, for rows that lead somewhere.
struct SettingsRowTile: View {
    var symbol: String
    var color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row that opens a web page: tile, title, explanation, and an outward arrow.
struct SettingsLinkRow<Tile: View>: View {
    var title: String
    var caption: String?
    var url: URL
    @ViewBuilder var tile: Tile

    var body: some View {
        Link(destination: url) {
            SettingsLeadingRow(title: title, caption: caption, trailingSymbol: "arrow.up.right") { tile }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The layout every navigating row shares: tile, title and caption, then a trailing glyph.
struct SettingsLeadingRow<Tile: View>: View {
    var title: String
    var caption: String?
    var trailingSymbol: String
    @ViewBuilder var tile: Tile

    var body: some View {
        HStack(spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                if let caption {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: trailingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

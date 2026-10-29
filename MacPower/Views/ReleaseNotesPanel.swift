import AppKit
import SwiftUI

enum ReleaseNotesPanel {
    @MainActor
    static func present(
        title: String,
        message: String? = nil,
        notes: String,
        primary: String,
        secondary: String? = nil,
        alternate: String? = nil,
        onPrimary: @escaping () -> Void = {},
        onAlternate: @escaping () -> Void = {}
    ) {
        let dismiss = ReleaseNotesDismissBox()
        let hosting = NSHostingView(rootView: ReleaseNotesCard(
            title: title,
            message: message,
            items: ReleaseNotes.paragraphs(in: notes),
            primary: primary,
            secondary: secondary,
            alternate: alternate,
            dismiss: dismiss
        ))
        let window = ReleaseNotesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let screenHeight = window.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let size = NSSize(
            width: 460,
            height: min(max(fitted.height, 120), screenHeight - 48)
        )
        window.setContentSize(size)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.masksToBounds = true
        dismiss.window = window
        dismiss.onPrimary = onPrimary
        dismiss.onAlternate = onAlternate

        let restoreAccessory = NSApp.activationPolicy() == .accessory
        if restoreAccessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.invalidateShadow()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.runModal(for: window)
        if restoreAccessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private final class ReleaseNotesWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ReleaseNotesDismissBox {
    weak var window: NSWindow?
    var onPrimary: () -> Void = {}
    var onAlternate: () -> Void = {}
    private var closed = false

    func confirm() { finish(onPrimary) }
    func chooseAlternate() { finish(onAlternate) }
    func dismiss() { finish {} }

    private func finish(_ action: () -> Void) {
        guard !closed else { return }
        closed = true
        NSApp.stopModal()
        window?.orderOut(nil)
        action()
    }
}

private struct ReleaseNotesCard: View {
    let title: String
    let message: String?
    let items: [String]
    let primary: String
    let secondary: String?
    let alternate: String?
    let dismiss: ReleaseNotesDismissBox

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !items.isEmpty {
                notes
            }
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { dismiss.dismiss() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var notes: some View {
        let rows = VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(item)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if items.count > 7 {
            ScrollView { rows }
                .frame(height: 300)
        } else {
            rows
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let secondary {
                Button(secondary) { dismiss.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Button(primary) { dismiss.confirm() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            if let alternate {
                Button(alternate) { dismiss.chooseAlternate() }
            }
        }
        .controlSize(.large)
    }
}

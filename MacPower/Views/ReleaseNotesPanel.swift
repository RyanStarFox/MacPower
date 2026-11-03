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
        onAlternate: @escaping () -> Void = {},
        onLater: @escaping () -> Void = {},
        install: UpdateInstallController? = nil,
        automaticTitle: String? = nil,
        automaticOn: Bool = true,
        onAutomatic: @escaping (Bool) -> Void = { _ in }
    ) {
        let dismiss = ReleaseNotesDismissBox()
        let hosting = NSHostingView(rootView: ReleaseNotesCard(
            title: title,
            message: message,
            items: ReleaseNotes.paragraphs(in: notes),
            primary: primary,
            secondary: secondary,
            alternate: alternate,
            dismiss: dismiss,
            install: install,
            automaticTitle: automaticTitle,
            automaticOn: automaticOn,
            onAutomatic: onAutomatic
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
        dismiss.onLater = onLater
        dismiss.resize = { [weak hosting, weak window] in
            guard let hosting, let window else { return }
            hosting.layoutSubtreeIfNeeded()
            let fitted = hosting.fittingSize
            let screenHeight = window.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(
                width: 460,
                height: min(max(fitted.height, 120), screenHeight - 48)
            ))
        }
        install?.onInstalled = { dismiss.installedAndQuit() }

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
    var onLater: () -> Void = {}
    var resize: (() -> Void)?
    private var closed = false

    func confirm() { finish(onPrimary) }
    func chooseAlternate() { finish(onAlternate) }
    func dismiss() { finish(onLater) }
    func installedAndQuit() {
        guard !closed else { return }
        closed = true
        NSApp.stopModal()
        window?.orderOut(nil)
        NSApp.terminate(nil)
    }

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
    let install: UpdateInstallController?
    let automaticTitle: String?
    @State private var automaticOn: Bool
    let onAutomatic: (Bool) -> Void

    init(
        title: String,
        message: String?,
        items: [String],
        primary: String,
        secondary: String?,
        alternate: String?,
        dismiss: ReleaseNotesDismissBox,
        install: UpdateInstallController?,
        automaticTitle: String?,
        automaticOn: Bool,
        onAutomatic: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.message = message
        self.items = items
        self.primary = primary
        self.secondary = secondary
        self.alternate = alternate
        self.dismiss = dismiss
        self.install = install
        self.automaticTitle = automaticTitle
        self.onAutomatic = onAutomatic
        _automaticOn = State(initialValue: automaticOn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !items.isEmpty {
                notes
            }
            if let automaticTitle {
                Toggle(automaticTitle, isOn: $automaticOn)
                    .onChange(of: automaticOn) { _, enabled in
                        onAutomatic(enabled)
                    }
            }
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if install?.phase != .installing {
                close()
            }
        }
        .onChange(of: install?.phase) { _, _ in
            DispatchQueue.main.async { dismiss.resize?() }
        }
    }

    private func close() {
        install?.cancel()
        dismiss.dismiss()
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

    @ViewBuilder
    private var buttons: some View {
        if let install {
            installButtons(install)
        } else {
            linkButtons
        }
    }

    private var linkButtons: some View {
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

    private func installButtons(_ install: UpdateInstallController) -> some View {
        UpdateInstallBar(
            install: install,
            laterTitle: secondary,
            primaryTitle: primary,
            alternateTitle: alternate,
            onLater: close,
            onPrimary: { dismiss.confirm() },
            onAlternate: { dismiss.chooseAlternate() },
            onLayout: { dismiss.resize?() }
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// AppKit buttons and a progress bar. SwiftUI often does not redraw an
/// `NSHostingView` while `NSApp.runModal` is running, so a click looked dead
/// even after the download had started.
private struct UpdateInstallBar: NSViewRepresentable {
    var install: UpdateInstallController
    var laterTitle: String?
    var primaryTitle: String
    var alternateTitle: String?
    var onLater: () -> Void
    var onPrimary: () -> Void
    var onAlternate: () -> Void
    var onLayout: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .trailing
        column.spacing = 8
        context.coordinator.build(in: column)
        return column
    }

    func updateNSView(_ column: NSStackView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    static func dismantleNSView(_ nsView: NSStackView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: UpdateInstallBar
        var column: NSStackView?
        var status: NSTextField?
        var progressRow: NSStackView?
        var row: NSStackView?
        var laterButton: NSButton?
        var progress: NSProgressIndicator?
        var percentLabel: NSTextField?
        var updateButton: NSButton?
        var primaryButton: NSButton?
        var alternateButton: NSButton?
        var timer: Timer?
        var lastPhase: UpdateInstallController.Phase?

        init(_ parent: UpdateInstallBar) {
            self.parent = parent
        }

        func build(in column: NSStackView) {
            self.column = column
            column.alignment = .leading
            column.translatesAutoresizingMaskIntoConstraints = false
            column.widthAnchor.constraint(equalToConstant: 420).isActive = true

            let status = NSTextField(wrappingLabelWithString: "")
            status.font = .systemFont(ofSize: 12)
            status.textColor = .secondaryLabelColor
            status.alignment = .left
            status.maximumNumberOfLines = 2
            status.preferredMaxLayoutWidth = 420
            status.isHidden = true
            column.addArrangedSubview(status)
            self.status = status

            let progressRow = NSStackView()
            progressRow.orientation = .horizontal
            progressRow.alignment = .centerY
            progressRow.spacing = 8
            progressRow.isHidden = true
            column.addArrangedSubview(progressRow)
            self.progressRow = progressRow

            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.controlSize = .regular
            bar.minValue = 0
            bar.maxValue = 1
            bar.isIndeterminate = true
            bar.usesThreadedAnimation = true
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
            progressRow.addArrangedSubview(bar)
            progress = bar

            let percent = NSTextField(labelWithString: "")
            percent.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            percent.textColor = .secondaryLabelColor
            percent.alignment = .right
            percent.translatesAutoresizingMaskIntoConstraints = false
            percent.setContentHuggingPriority(.required, for: .horizontal)
            percent.setContentCompressionResistancePriority(.required, for: .horizontal)
            progressRow.addArrangedSubview(percent)
            percentLabel = percent

            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            column.addArrangedSubview(row)
            self.row = row

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)

            if parent.laterTitle != nil {
                let later = button(parent.laterTitle ?? "", action: #selector(laterClicked), key: "\u{1b}")
                row.addArrangedSubview(later)
                laterButton = later
            }

            let update = button(parent.install.text.update, action: #selector(updateClicked), key: "\r")
            row.addArrangedSubview(update)
            updateButton = update

            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sync()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .modalPanel)
            self.timer = timer
            sync()
        }

        func button(_ title: String, action: Selector, key: String) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.keyEquivalent = key
            return button
        }

        @objc func updateClicked() {
            parent.install.start()
            sync()
        }

        @objc func laterClicked() {
            parent.onLater()
        }

        @objc func primaryClicked() {
            parent.onPrimary()
        }

        @objc func alternateClicked() {
            parent.onAlternate()
        }

        func sync() {
            let install = parent.install
            let busy = install.phase != .ready && install.phase != .failed
            let text = install.statusText
            status?.stringValue = text
            status?.isHidden = text.isEmpty
            updateButton?.title = install.text.update
            updateButton?.isEnabled = !busy
            laterButton?.isEnabled = install.phase != .installing

            progressRow?.isHidden = !busy
            if busy {
                if let fraction = install.fraction {
                    progress?.isIndeterminate = false
                    progress?.doubleValue = fraction
                    progress?.stopAnimation(nil)
                    percentLabel?.stringValue = install.progressDetail
                } else if progress?.isIndeterminate != true {
                    progress?.isIndeterminate = true
                    progress?.startAnimation(nil)
                    percentLabel?.stringValue = install.progressDetail
                } else {
                    progress?.startAnimation(nil)
                    percentLabel?.stringValue = install.progressDetail
                }
            } else {
                progress?.stopAnimation(nil)
                percentLabel?.stringValue = ""
            }

            if case .failed = install.phase {
                if primaryButton == nil, let row {
                    let primary = button(parent.primaryTitle, action: #selector(primaryClicked), key: "")
                    row.addArrangedSubview(primary)
                    primaryButton = primary
                    if let alternateTitle = parent.alternateTitle {
                        let alternate = button(alternateTitle, action: #selector(alternateClicked), key: "")
                        row.addArrangedSubview(alternate)
                        alternateButton = alternate
                    }
                }
            }

            if install.phase != lastPhase {
                let previous = lastPhase
                lastPhase = install.phase
                if previous != nil {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.onLayout()
                    }
                }
            }
        }
    }
}

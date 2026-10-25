import AppKit
import SwiftUI

/// Плавающая панель, которая не активирует приложение: целевое приложение остаётся активным,
/// а выделение в его поле ввода — нетронутым. Панель становится key, чтобы ловить Esc и Return.
final class PreviewPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: PreviewPanelController.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PreviewPanelController {
    static let size = CGSize(width: 560, height: 440)

    private var panel: PreviewPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ model: PreviewModel, models: ModelStore, anchor: CGRect?) {
        let panel = panel ?? PreviewPanel()
        panel.contentView = NSHostingView(rootView: PreviewView(model: model, models: models))
        panel.onCancel = { model.onCancel() }

        let anchor = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Self.size)
        panel.setFrame(PanelPlacement.frame(size: Self.size, anchor: anchor, visible: visible), display: true)

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func bringToFront() {
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

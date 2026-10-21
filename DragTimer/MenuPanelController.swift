import AppKit
import SwiftUI

/// Menu panel pinned under the status item.
///
/// Size is owned entirely by us (no SwiftUI intrinsic window resizing).
/// Every frame change sets origin from `visibleFrame.maxY` so Settings ↔ Back
/// cannot leave a gap under the menu bar.
@MainActor
final class MenuPanelController {
    private let panel: NSPanel
    private let hostingController: NSHostingController<TimerListView>
    private var clickOutsideLocal: Any?
    private var clickOutsideGlobal: Any?
    private weak var anchor: NSView?

    private let store: TimerStore
    private let width: CGFloat = 360
    /// Explicit heights — avoids GeometryReader / intrinsic-size races.
    private let mainHeight: CGFloat = 300
    private let settingsHeight: CGFloat = 360
    private var pinnedTop: CGFloat?

    var isVisible: Bool { panel.isVisible }

    var statusButtonProvider: (() -> NSView?)?

    var onDragHandleChanged: ((CGFloat, NSEvent.ModifierFlags) -> Void)?
    var onDragHandleEnded: ((CGFloat, NSEvent.ModifierFlags) -> Void)?

    init(store: TimerStore) {
        self.store = store

        hostingController = NSHostingController(
            rootView: TimerListView(store: store, launchAtLogin: .shared)
        )
        // Critical: we own sizing. Intrinsic sizing resizes from the bottom-left
        // and is what caused the Settings→Back gap.
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: mainHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentViewController = hostingController

        refreshRoot()
    }

    func toggle(relativeTo anchor: NSView) {
        if panel.isVisible { hide() } else { show(relativeTo: anchor) }
    }

    func show(relativeTo anchor: NSView) {
        self.anchor = anchor
        refreshRoot()
        pinnedTop = nil
        place(height: mainHeight)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Re-assert after AppKit commits first layout.
        place(height: mainHeight)
        installClickOutsideMonitor()
    }

    func hide() {
        removeClickOutsideMonitor()
        panel.orderOut(nil)
        pinnedTop = nil
    }

    private func refreshRoot() {
        hostingController.rootView = TimerListView(
            store: store,
            launchAtLogin: .shared,
            onDragHandleChanged: { [weak self] distance, flags in
                self?.onDragHandleChanged?(distance, flags)
            },
            onDragHandleEnded: { [weak self] distance, flags in
                self?.onDragHandleEnded?(distance, flags)
            },
            onShowingSettingsChange: { [weak self] showing in
                guard let self else { return }
                self.place(height: showing ? self.settingsHeight : self.mainHeight)
            },
            startsInSettings: false,
            presentationID: UUID()
        )
    }

    /// Sets frame with the top edge locked under the menu bar.
    private func place(height: CGFloat) {
        let h = max(height, 120)
        let anchorX = resolvedAnchorX()
        guard let screen = resolvedScreen(for: anchorX) else { return }

        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        let top = pinnedTop ?? (visible.maxY - gap)
        pinnedTop = top

        var origin = NSPoint(
            x: anchorX - width / 2,
            y: top - h
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
        if origin.y < visible.minY + 8 {
            origin.y = visible.minY + 8
        }

        let frame = NSRect(origin: origin, size: NSSize(width: width, height: h))
        panel.setFrame(frame, display: true, animate: false)
        hostingController.view.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func resolvedAnchorX() -> CGFloat {
        if let anchor, let window = anchor.window {
            let local = anchor.convert(anchor.bounds, to: nil)
            let screenRect = window.convertToScreen(local)
            if screenRect.width > 0 { return screenRect.midX }
        }
        if let button = statusButtonProvider?(), let window = button.window {
            let local = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(local)
            if screenRect.width > 0 { return screenRect.midX }
        }
        return NSEvent.mouseLocation.x
    }

    private func resolvedScreen(for anchorX: CGFloat) -> NSScreen? {
        if let anchor, let screen = anchor.window?.screen { return screen }
        if let button = statusButtonProvider?(), let screen = button.window?.screen { return screen }
        return NSScreen.screens.first(where: { $0.frame.minX <= anchorX && anchorX <= $0.frame.maxX })
            ?? NSScreen.main
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        // Local: clicks inside our app (other windows, etc.).
        clickOutsideLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.shouldDismissForOutsideClick() { self.hide() }
            return event
        }

        // Global: clicks on the desktop / other apps — local monitors never see these.
        clickOutsideGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.shouldDismissForOutsideClick() { self.hide() }
            }
        }
    }

    private func shouldDismissForOutsideClick() -> Bool {
        guard panel.isVisible else { return false }
        let point = NSEvent.mouseLocation
        // Stay open when clicking the panel itself.
        if panel.frame.insetBy(dx: -2, dy: -2).contains(point) { return false }
        // Status-item click is owned by MenuBarController (toggle / drag).
        if isMouseOverStatusButton(point) { return false }
        return true
    }

    private func isMouseOverStatusButton(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusButtonProvider?(), let window = button.window else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let buttonPoint = button.convert(windowPoint, from: nil)
        return button.bounds.insetBy(dx: -6, dy: -6).contains(buttonPoint)
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideLocal {
            NSEvent.removeMonitor(clickOutsideLocal)
            self.clickOutsideLocal = nil
        }
        if let clickOutsideGlobal {
            NSEvent.removeMonitor(clickOutsideGlobal)
            self.clickOutsideGlobal = nil
        }
    }
}

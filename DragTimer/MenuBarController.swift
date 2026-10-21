import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let menuPanel: MenuPanelController
    private let store: TimerStore
    private let hud = DragHUDController()
    private let capture = DragCaptureOverlay()
    private var cancellables = Set<AnyCancellable>()
    private var dragStart: NSPoint?
    private var currentDuration: TimeInterval = 0
    private var isDragging = false
    private var capturing = false
    /// Menu was open when the status-item press began. Stops the click handler
    /// and the macOS 27 expanded-interface callback from immediately re-opening.
    private var suppressMenuShow = false
    private var statusMouseMonitor: Any?
    private var statusGlobalMouseMonitor: Any?

    init(store: TimerStore) {
        self.store = store
        self.menuPanel = MenuPanelController(store: store)
        super.init()
        configureCapture()
        configureStatusItem()
        configureMenuPanel()
        observeStore()
        installStatusMouseMonitor()
        updateMenuBar()
        CompletionAlerter.shared.statusButtonProvider = { [weak self] in self?.statusItem?.button }
    }

    private func configureCapture() {
        capture.onDragBegan = { [weak self] point in self?.dragBegan(at: point) }
        capture.onDragChanged = { [weak self] point, flags in self?.dragChanged(at: point, flags: flags) }
        capture.onDragEnded = { [weak self] point, flags in self?.dragEnded(at: point, flags: flags) }
        capture.onCancelled = { [weak self] in self?.dragCancelled() }
        capture.onClick = { [weak self] in self?.handleClick() }
    }

    private func configureMenuPanel() {
        menuPanel.statusButtonProvider = { [weak self] in self?.statusItem?.button }
        menuPanel.onDragHandleChanged = { [weak self] distance, flags in
            self?.handlePopoverDrag(distance: distance, flags: flags)
        }
        menuPanel.onDragHandleEnded = { [weak self] distance, flags in
            self?.finishPopoverDrag(distance: distance, flags: flags)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.isVisible = true
        item.autosaveName = "DragTimer.StatusItem"

        guard let button = item.button else {
            NSLog("DragTimer: NSStatusItem.button was nil")
            return
        }

        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "DragTimer")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "DragTimer — drag to start a timer"

        if #available(macOS 27.0, *) {
            item.expandedInterfaceDelegate = self
        } else {
            button.target = self
            button.action = #selector(legacyClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func installStatusMouseMonitor() {
        statusMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.isMouseOverStatusButton() else { return event }

            if event.type == .rightMouseDown {
                self.showContextMenu()
                return nil
            }

            self.beginCapture()
            return nil
        }

        statusGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isMouseOverStatusButton(), !self.capturing else { return }
                self.beginCapture()
            }
        }
    }

    private func isMouseOverStatusButton() -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let buttonPoint = button.convert(windowPoint, from: nil)
        return button.bounds.insetBy(dx: -4, dy: -4).contains(buttonPoint)
    }

    private func observeStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBar() }
            .store(in: &cancellables)
    }

    @objc private func legacyClick(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        handleClick()
    }

    private func beginCapture() {
        guard !capturing else { return }
        capturing = true
        if menuPanel.isVisible {
            suppressMenuShow = true
            hideMenu()
        }
        capture.begin(from: NSEvent.mouseLocation)
    }

    // MARK: - Click / menu

    private func handleClick() {
        capturing = false
        // Press already dismissed the panel — treat this click as "close".
        if suppressMenuShow {
            suppressMenuShow = false
            dismissExpandedInterface()
            return
        }
        guard let button = statusItem.button else { return }
        if menuPanel.isVisible {
            dismissExpandedInterface()
        } else {
            menuPanel.show(relativeTo: button)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        menuPanel.show(relativeTo: button)
    }

    private func hideMenu() {
        menuPanel.hide()
    }

    private func dismissExpandedInterface() {
        hideMenu()
        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceSession?.cancel()
        }
    }

    // MARK: - Menubar drag

    private func dragBegan(at point: NSPoint) {
        isDragging = true
        dragStart = point
        currentDuration = 0
        hud.show(near: point)
    }

    private func dragChanged(at point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard isDragging, let start = dragStart else { return }
        let distance = hypot(point.x - start.x, point.y - start.y)
        let option = flags.contains(.option)
        let precision = flags.contains(.shift)
        currentDuration = DurationMapper.seconds(for: distance, optionMultiplier: option, precisionMode: precision)
        hud.update(duration: currentDuration, near: point, option: option, precision: precision)
    }

    private func dragEnded(at point: NSPoint, flags: NSEvent.ModifierFlags) {
        dragChanged(at: point, flags: flags)
        hud.hide()
        let duration = currentDuration
        isDragging = false
        capturing = false
        dragStart = nil
        currentDuration = 0
        if duration >= 60 {
            _ = store.addTimer(seconds: duration)
            showMenu()
        }
    }

    private func dragCancelled() {
        hud.hide()
        isDragging = false
        capturing = false
        suppressMenuShow = false
        dragStart = nil
        currentDuration = 0
    }

    // MARK: - Header drag-handle fallback

    private func handlePopoverDrag(distance: CGFloat, flags: NSEvent.ModifierFlags) {
        let option = flags.contains(.option)
        let precision = flags.contains(.shift)
        currentDuration = DurationMapper.seconds(for: distance, optionMultiplier: option, precisionMode: precision)
        let cursor = NSEvent.mouseLocation
        hud.show(near: cursor)
        hud.update(duration: currentDuration, near: cursor, option: option, precision: precision)
    }

    private func finishPopoverDrag(distance: CGFloat, flags: NSEvent.ModifierFlags) {
        handlePopoverDrag(distance: distance, flags: flags)
        hud.hide()
        let duration = currentDuration
        currentDuration = 0
        if duration >= 60 {
            _ = store.addTimer(seconds: duration)
        }
    }

    // MARK: - Context menu

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "1 minute timer", action: #selector(add1Minute), keyEquivalent: "")
        menu.addItem(withTitle: "5 minute timer", action: #selector(add5Minutes), keyEquivalent: "")
        menu.addItem(withTitle: "15 minute timer", action: #selector(add15Minutes), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DragTimer", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: 0), in: button)
    }

    @objc private func add1Minute() { _ = store.addTimer(seconds: 60) }
    @objc private func add5Minutes() { _ = store.addTimer(seconds: 5 * 60) }
    @objc private func add15Minutes() { _ = store.addTimer(seconds: 15 * 60) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: - Appearance

    private func updateMenuBar() {
        guard let button = statusItem?.button else { return }

        guard let next = store.activeTimers.first else {
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
            button.toolTip = "DragTimer — drag to start a timer"
            return
        }

        let remaining = max(0, Int(next.dueAt.timeIntervalSinceNow))
        let countdown: String
        if remaining >= 3600 {
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            countdown = String(format: "%d:%02d", h, m)
        } else {
            let m = remaining / 60
            let s = remaining % 60
            countdown = String(format: "%02d:%02d", m, s)
        }

        button.title = countdown
        button.imagePosition = .imageLeading
        statusItem.length = NSStatusItem.variableLength
        button.toolTip = "\(next.displayTitle) — \(countdown) remaining"
    }
}

@available(macOS 27.0, *)
extension MenuBarController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        if capturing || isDragging || suppressMenuShow {
            session.cancel()
            return
        }
        if !menuPanel.isVisible {
            showMenu()
        }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        // Our panel is owned by click / click-outside, not the system session.
        // Only hide when we are not mid-capture (capture already manages visibility).
        if !capturing && !menuPanel.isVisible {
            // Session ended after we already closed — nothing to do.
            return
        }
        // Do not auto-hide here: ending the session on outside-click would race
        // with our own click-outside monitor and cause open/close flicker.
    }
}

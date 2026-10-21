import AppKit

/// Full-screen transparent panel that owns the Gestimer drag after mouse-down
/// on the status item. Showing this immediately prevents macOS 27 Mission Control
/// from stealing the downward drag from the menu bar.
@MainActor
final class DragCaptureOverlay {
    private var panel: NSPanel?
    private var canvas: DragLineCanvas?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var pollTimer: Timer?
    private var active = false

    var onDragBegan: ((NSPoint) -> Void)?
    var onDragChanged: ((NSPoint, NSEvent.ModifierFlags) -> Void)?
    var onDragEnded: ((NSPoint, NSEvent.ModifierFlags) -> Void)?
    var onClick: (() -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: NSPoint = .zero
    private var dragging = false
    private let dragThreshold: CGFloat = 5

    func begin(from start: NSPoint) {
        cancel(silent: true)
        active = true
        startPoint = start
        dragging = false

        let frame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let canvas = DragLineCanvas(frame: NSRect(origin: .zero, size: frame.size))
        canvas.origin = start
        canvas.cursor = start
        canvas.isActive = false
        panel.contentView = canvas
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.canvas = canvas

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if self.isEscape(event) {
                    self.cancel(silent: false)
                    return nil
                }
                return event
            }
            self.handle(event)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.type == .keyDown {
                    if self.isEscape(event) { self.cancel(silent: false) }
                    return
                }
                self.handle(event)
            }
        }

        // Dedicated local key monitor so Escape works even if focus is odd.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.active, self.isEscape(event) else { return event }
            self.cancel(silent: false)
            return nil
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}"
    }

    private func poll() {
        guard active else { return }
        let pressed = NSEvent.pressedMouseButtons & (1 << 0) != 0
        let point = NSEvent.mouseLocation
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if pressed {
            updateDrag(to: point, flags: flags)
        } else {
            finish(at: point, flags: flags)
        }
    }

    private func handle(_ event: NSEvent) {
        guard active else { return }
        let point = NSEvent.mouseLocation
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.type {
        case .leftMouseDragged:
            updateDrag(to: point, flags: flags)
        case .flagsChanged:
            guard NSEvent.pressedMouseButtons & (1 << 0) != 0 else { return }
            updateDrag(to: point, flags: flags)
        case .leftMouseUp:
            finish(at: point, flags: flags)
        default:
            break
        }
    }

    private func updateDrag(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
        if !dragging, distance >= dragThreshold {
            dragging = true
            canvas?.isActive = true
            canvas?.origin = startPoint
            onDragBegan?(startPoint)
        }
        if dragging {
            canvas?.cursor = point
            let duration = DurationMapper.seconds(
                for: distance,
                optionMultiplier: flags.contains(.option),
                precisionMode: flags.contains(.shift)
            )
            canvas?.progress = duration >= 60 ? 1 : max(0, min(0.95, CGFloat(distance / 80)))
            onDragChanged?(point, flags)
        }
    }

    private func finish(at point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard active else { return }
        let wasDragging = dragging
        if wasDragging {
            onDragChanged?(point, flags)
            onDragEnded?(point, flags)
        }
        teardown()
        if !wasDragging {
            onClick?()
        }
    }

    func cancel(silent: Bool = false) {
        let wasActive = active
        teardown()
        // Always notify so the controller clears `capturing`, even if the
        // pointer never crossed the drag threshold before Escape.
        if !silent, wasActive {
            onCancelled?()
        }
    }

    private func teardown() {
        active = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        canvas?.isActive = false
        canvas = nil
        panel?.orderOut(nil)
        panel = nil
        dragging = false
    }
}

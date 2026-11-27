import AppKit
import CoreGraphics

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Full-screen transparent panels (one per screen) that own the Gestimer drag
/// after mouse-down on the status item. Per-screen panels ensure the drag line
/// renders across all displays even when "Displays have separate Spaces" is on.
@MainActor
final class DragCaptureOverlay {
    private var panels: [OverlayPanel] = []
    private var canvases: [DragLineCanvas] = []
    private weak var keyPanel: OverlayPanel?
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

        let screens = NSScreen.screens
        for screen in screens {
            let frame = screen.frame
            let panel = OverlayPanel(
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
            panels.append(panel)
            canvases.append(canvas)
            if frame.contains(start) {
                keyPanel = panel
            }
        }
        if keyPanel == nil {
            keyPanel = panels.first
        }

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
        if CGEventSource.keyState(.combinedSessionState, key: 53) {
            cancel(silent: false)
            return
        }
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
            NSApp.activate(ignoringOtherApps: true)
            keyPanel?.makeKeyAndOrderFront(nil)
            for canvas in canvases {
                canvas.isActive = true
                canvas.origin = startPoint
            }
            onDragBegan?(startPoint)
        }
        if dragging {
            let duration = DurationMapper.seconds(
                for: distance,
                optionMultiplier: flags.contains(.option),
                precisionMode: flags.contains(.shift)
            )
            let progress: CGFloat = duration >= 60 ? 1 : max(0, min(0.95, CGFloat(distance / 80)))
            for canvas in canvases {
                canvas.cursor = point
                canvas.progress = progress
            }
            onDragChanged?(point, flags)
        }
    }

    private func finish(at point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard active else { return }
        let wasDragging = dragging
        teardown()
        if wasDragging {
            onDragChanged?(point, flags)
            onDragEnded?(point, flags)
        } else {
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
        for canvas in canvases {
            canvas.isActive = false
        }
        canvases.removeAll()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        keyPanel = nil
        dragging = false
    }
}

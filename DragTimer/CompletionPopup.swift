import AppKit
import SwiftUI

@MainActor
final class CompletionPopupModel: ObservableObject {
    @Published var title = "Timer"
    @Published var endedAt = ""
    var onDismiss: (() -> Void)?
    var onSnooze: (() -> Void)?
}

struct CompletionPopupView: View {
    @ObservedObject var model: CompletionPopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(model.endedAt)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text("Timer finished")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Dismiss") { model.onDismiss?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("+5 min") { model.onSnooze?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 280, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        }
    }
}

/// Compact banner under the menu-bar icon — bypasses Focus / DND.
@MainActor
final class CompletionPopupController {
    private let model = CompletionPopupModel()
    private let panel: NSPanel
    private let hosting: NSHostingView<CompletionPopupView>
    private var queue: [TimerItem] = []
    private var current: TimerItem?
    private weak var anchor: NSView?

    var onSnooze: ((UUID) -> Void)?

    init() {
        hosting = NSHostingView(rootView: CompletionPopupView(model: model))
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        model.onDismiss = { [weak self] in self?.advance() }
        model.onSnooze = { [weak self] in self?.snoozeCurrent() }
    }

    func present(_ timer: TimerItem, relativeTo anchor: NSView) {
        self.anchor = anchor
        queue.append(timer)
        if current == nil {
            showFront()
        }
    }

    func dismissAll() {
        queue.removeAll()
        current = nil
        panel.orderOut(nil)
    }

    private func showFront() {
        guard let timer = queue.first else {
            current = nil
            panel.orderOut(nil)
            return
        }
        queue.removeFirst()
        current = timer
        apply(timer)
        resizeAndPosition()
        panel.orderFrontRegardless()
    }

    private func advance() {
        current = nil
        if queue.isEmpty {
            panel.orderOut(nil)
        } else {
            showFront()
        }
    }

    private func snoozeCurrent() {
        guard let id = current?.id else { return }
        current = nil
        panel.orderOut(nil)
        onSnooze?(id)
        if !queue.isEmpty {
            showFront()
        }
    }

    private func apply(_ timer: TimerItem) {
        model.title = timer.displayTitle
        model.endedAt = Self.timeFormatter.string(from: timer.completedAt ?? Date())
        hosting.rootView = CompletionPopupView(model: model)
    }

    private func resizeAndPosition() {
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 10 || size.height < 10 {
            size = NSSize(width: 280, height: 96)
        }
        size.width = 280
        size.height = max(size.height, 88)
        panel.setContentSize(size)

        // Horizontal: center on the status item when we can read it; else mouse X.
        // Vertical: always pin just under the menu bar via visibleFrame.maxY.
        // Status-item convertToScreen Y is unreliable on macOS 27 and was pushing
        // the panel above the top of the display.
        let anchorX: CGFloat = {
            if let anchor, let window = anchor.window {
                let local = anchor.convert(anchor.bounds, to: nil)
                let screenRect = window.convertToScreen(local)
                if screenRect.width > 0 { return screenRect.midX }
            }
            return NSEvent.mouseLocation.x
        }()

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchorX, y: NSEvent.mouseLocation.y)) })
            ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let gap: CGFloat = 10
        var origin = NSPoint(
            x: anchorX - size.width / 2,
            y: visible.maxY - size.height - gap
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - gap)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

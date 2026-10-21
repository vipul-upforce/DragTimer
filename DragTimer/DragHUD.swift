import AppKit
import SwiftUI
import Combine

@MainActor
final class DragHUDModel: ObservableObject {
    @Published var label = "Drag farther"
    @Published var fireAt = ""
    @Published var detail = "Keep dragging"
    @Published var isReady = false
}

struct DragHUDView: View {
    @ObservedObject var model: DragHUDModel

    var body: some View {
        VStack(spacing: 6) {
            Text(model.label)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.isReady ? Color.primary : Color.secondary)

            if !model.fireAt.isEmpty {
                Text(model.fireAt)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(model.detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("esc cancels")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(minWidth: 210)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

@MainActor
final class DragHUDController {
    let model = DragHUDModel()
    private let panel: NSPanel
    private let hosting: NSHostingView<DragHUDView>

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        // e.g. "Thu 15:45" / "Thu 3:45 PM" — weekday when crossing midnight.
        f.setLocalizedDateFormatFromTemplate("EEE jm")
        return f
    }()

    init() {
        hosting = NSHostingView(rootView: DragHUDView(model: model))
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = hosting
    }

    func show(near point: NSPoint) {
        model.label = "Drag farther"
        model.fireAt = ""
        model.detail = "Keep dragging"
        model.isReady = false
        resizeToFit()
        updatePosition(near: point)
        panel.orderFrontRegardless()
    }

    func update(duration: TimeInterval, near point: NSPoint, option: Bool, precision: Bool) {
        model.label = DurationMapper.label(for: duration)
        model.isReady = duration >= 60
        model.fireAt = Self.fireAtLabel(for: duration)

        if duration < 60 {
            model.detail = "Keep dragging"
        } else if option {
            model.detail = "⌥ ×4 · release to start"
        } else if precision {
            model.detail = "⇧ fine · release to start"
        } else {
            model.detail = "⌥ longer · ⇧ fine · release"
        }

        resizeToFit()
        updatePosition(near: point)
    }

    func hide() { panel.orderOut(nil) }

    /// Time always; date only when the alert lands on another calendar day.
    private static func fireAtLabel(for duration: TimeInterval) -> String {
        guard duration >= 60 else { return "" }
        let fireDate = Date().addingTimeInterval(duration)
        if Calendar.current.isDateInToday(fireDate) {
            return timeFormatter.string(from: fireDate)
        }
        return dateTimeFormatter.string(from: fireDate)
    }

    private func resizeToFit() {
        hosting.rootView = DragHUDView(model: model)
        var size = hosting.fittingSize
        size.width = max(size.width, 210)
        size.height = max(size.height, 88)
        panel.setContentSize(size)
    }

    private func updatePosition(near point: NSPoint) {
        let size = panel.frame.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 28)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 10), visible.maxX - size.width - 10)
            origin.y = min(max(origin.y, visible.minY + 10), visible.maxY - size.height - 10)
        }
        panel.setFrameOrigin(origin)
    }
}

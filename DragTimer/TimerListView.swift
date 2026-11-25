import SwiftUI
import AppKit

struct TimerListView: View {
    @ObservedObject var store: TimerStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var alerts = AlertPreferences.shared
    var onDragHandleChanged: ((CGFloat, NSEvent.ModifierFlags) -> Void)? = nil
    var onDragHandleEnded: ((CGFloat, NSEvent.ModifierFlags) -> Void)? = nil
    /// Fired synchronously when Settings is opened/closed so the panel can
    /// resize while keeping its top edge pinned under the menu bar.
    var onShowingSettingsChange: ((Bool) -> Void)? = nil
    var startsInSettings: Bool = false
    var initialFocusTimerID: UUID? = nil
    /// Bumped on each panel open so SwiftUI drops preserved `@State` (e.g. settings).
    var presentationID: UUID = UUID()
    @State private var showingSettings = false
    @State private var remindersAccessDenied = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                settingsHeader
                Divider()
                settingsContent
                Spacer(minLength: 0)
            } else {
                header
                Divider()
                content
                Spacer(minLength: 0)
            }
        }
        .frame(width: 360, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .id(presentationID)
        .onAppear {
            showingSettings = startsInSettings
        }
        .onChange(of: showingSettings) { isSettings in
            if isSettings {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            onShowingSettingsChange?(isSettings)
        }
    }

    // MARK: - Main

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if onDragHandleChanged != nil {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("DragTimer")
                        .font(.headline)
                    Text("· drag to set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("DragTimer")
                        .font(.headline)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .gesture(headerDragGesture)
            .help(onDragHandleChanged != nil ? "Drag this row to set a timer · ⌥ longer · ⇧ precise" : "DragTimer")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit DragTimer")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard onDragHandleChanged != nil else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                onDragHandleChanged?(distance, NSEvent.modifierFlags)
            }
            .onEnded { value in
                guard onDragHandleEnded != nil else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                onDragHandleEnded?(distance, NSEvent.modifierFlags)
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.activeTimers.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 27))
                    .foregroundStyle(.secondary)
                Text("No active timers").font(.headline)
                Text("Drag the icon, or start one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                quickButtons
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.activeTimers) { timer in
                            TimerRow(
                                timer: timer,
                                store: store,
                                autoFocus: timer.id == initialFocusTimerID
                            )
                            .id(timer.id)
                            Divider().padding(.leading, 14)
                        }
                        quickButtons.padding(.vertical, 12)
                    }
                }
                .frame(maxHeight: 360)
                .onAppear {
                    if let initialFocusTimerID {
                        proxy.scrollTo(initialFocusTimerID, anchor: .center)
                    }
                }
            }
        }
    }

    private var quickButtons: some View {
        HStack(spacing: 7) {
            ForEach([(5, "5m"), (15, "15m"), (30, "30m"), (60, "1h")], id: \.0) { item in
                Button(item.1) { _ = store.addTimer(seconds: TimeInterval(item.0 * 60)) }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Settings

    private var settingsHeader: some View {
        HStack(spacing: 8) {
            Button {
                showingSettings = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Settings").font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Back")
            .accessibilityLabel("Back")

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("When a timer finishes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            settingsRow("Menu popup", isOn: $alerts.showMenuPopup)
            settingsRow("Play sound", isOn: $alerts.playSound)
            settingsRow("System notification", isOn: $alerts.systemNotifications)

            if alerts.systemNotifications, notifications.authorizationStatus == .denied {
                HStack(spacing: 6) {
                    Text("Notifications blocked in System Settings")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open") {
                        NotificationManager.shared.openSystemSettings()
                    }
                    .controlSize(.mini)
                }
                .padding(.top, 6)
            }

            Text("Menu popup still works in Focus / Do Not Disturb.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Divider().padding(.vertical, 12)

            Text("General")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            if remindersAccessDenied {
                Text("Reminders access denied in System Settings")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 6)
            }

            settingsRow("Apple Reminders", isOn: Binding(
                get: { store.syncToReminders },
                set: { newValue in
                    store.syncToReminders = newValue
                    if newValue {
                        ReminderSync.shared.requestAccess { granted in
                            remindersAccessDenied = !granted
                        }
                    }
                }
            ))
            settingsRow("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .onAppear {
            NotificationManager.shared.refreshAuthorizationStatus()
        }
        .onChange(of: alerts.systemNotifications) { enabled in
            if enabled { NotificationManager.shared.requestAuthorization() }
        }
    }

    private func settingsRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(minHeight: 28)
    }
}

private struct TimerRow: View {
    let timer: TimerItem
    @ObservedObject var store: TimerStore
    let autoFocus: Bool
    @State private var title: String = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                LabelTextField(
                    text: $title,
                    placeholder: "Add reminder label…",
                    autoFocus: autoFocus,
                    isEditing: $isEditing,
                    onChange: { newValue in
                        store.updateTitle(id: timer.id, title: newValue)
                    },
                    onCommit: { finalValue in
                        store.updateTitle(id: timer.id, title: finalValue)
                    }
                )
                .frame(height: 20)
                .padding(.horizontal, isEditing ? 6 : 0)
                .padding(.vertical, isEditing ? 2 : 0)
                .background {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                            }
                    }
                }
                Text(remainingText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.snooze(id: timer.id, minutes: 5) } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Reset to 5 minutes")
            Button { store.cancel(id: timer.id) } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Cancel timer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            title = timer.title
        }
        .onChange(of: timer.title) { newValue in
            if title != newValue {
                title = newValue
            }
        }
    }

    private var remainingText: String {
        let remaining = max(0, Int(timer.dueAt.timeIntervalSinceNow))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

private struct LabelTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let autoFocus: Bool
    @Binding var isEditing: Bool
    let onChange: (String) -> Void
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text, nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
        if autoFocus && !context.coordinator.didAutoFocus {
            context.coordinator.scheduleAutoFocus(for: nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LabelTextField
        var originalText: String = ""
        var didAutoFocus = false

        init(_ parent: LabelTextField) {
            self.parent = parent
            self.originalText = parent.text
        }

        func scheduleAutoFocus(for field: NSTextField) {
            didAutoFocus = true
            let delays: [TimeInterval] = [0.02, 0.08, 0.18]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak field] in
                    guard let field, let window = field.window, window.isVisible else { return }
                    if field.currentEditor() != nil { return }
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(field)
                }
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            originalText = field.stringValue
            DispatchQueue.main.async {
                self.parent.isEditing = true
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            parent.text = value
            parent.onChange(value)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            originalText = value
            parent.text = value
            parent.onCommit(value)
            DispatchQueue.main.async {
                self.parent.isEditing = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                field.stringValue = originalText
                parent.text = originalText
                parent.onChange(originalText)
                field.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let value = field.stringValue
                originalText = value
                parent.text = value
                parent.onCommit(value)
                field.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

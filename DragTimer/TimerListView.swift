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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.activeTimers) { timer in
                        TimerRow(timer: timer, store: store)
                        Divider().padding(.leading, 14)
                    }
                    quickButtons.padding(.vertical, 12)
                }
            }
            .frame(maxHeight: 360)
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
    @State private var title: String = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Timer title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit { store.updateTitle(id: timer.id, title: title) }
                    .onChange(of: title) { newValue in
                        store.updateTitle(id: timer.id, title: newValue)
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
        .onAppear { title = timer.title }
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

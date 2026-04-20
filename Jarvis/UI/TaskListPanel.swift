import SwiftUI
import EventKit

// MARK: - Root panel

struct TaskListPanel: View {
    @StateObject private var store = TaskListStore.shared
    @State private var selectedTab: Tab = .events

    enum Tab { case events, reminders }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "日程", icon: "calendar", selected: selectedTab == .events) {
                    selectedTab = .events
                }
                TabButton(title: "提醒", icon: "checkmark.circle", selected: selectedTab == .reminders) {
                    selectedTab = .reminders
                }
                Spacer()
                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
            .padding(.leading, 6)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if store.isLoading {
                Spacer()
                ProgressView().scaleEffect(0.8)
                Spacer()
            } else {
                Group {
                    if selectedTab == .events {
                        EventsTab(today: store.todayEvents, upcoming: store.upcomingEvents)
                    } else {
                        RemindersTab(
                            incomplete: store.incompleteReminders,
                            completed: store.completedReminders,
                            onToggle: { store.toggleReminder($0) }
                        )
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: selectedTab)
            }
        }
        .frame(width: 320, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { store.reload() }
    }
}

// MARK: - Tab button

private struct TabButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Events tab

private struct EventsTab: View {
    let today: [CalendarEventItem]
    let upcoming: [CalendarEventItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    if today.isEmpty {
                        EmptyHint(text: "今天没有日程")
                    } else {
                        ForEach(today) { event in
                            EventRow(event: event)
                            if event.id != today.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "今天")
                }

                Section {
                    if upcoming.isEmpty {
                        EmptyHint(text: "未来 7 天没有日程")
                    } else {
                        ForEach(upcoming) { event in
                            EventRow(event: event)
                            if event.id != upcoming.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "接下来 7 天")
                }
            }
            .padding(.bottom, 8)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEventItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Calendar color dot
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(cgColor: event.calendarColor))
                .frame(width: 4, height: 36)
                .padding(.leading, 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if event.isAllDay {
                        Text("全天")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(event.startDate, style: .time)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("–")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(event.endDate, style: .time)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let loc = event.location, !loc.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                        Text(loc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Reminders tab

private struct RemindersTab: View {
    let incomplete: [ReminderItem]
    let completed: [ReminderItem]
    let onToggle: (ReminderItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    if incomplete.isEmpty {
                        EmptyHint(text: "没有待办事项")
                    } else {
                        ForEach(incomplete) { item in
                            ReminderRow(item: item, onToggle: onToggle)
                            if item.id != incomplete.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "待完成")
                }

                if !completed.isEmpty {
                    Section {
                        ForEach(completed) { item in
                            ReminderRow(item: item, onToggle: onToggle)
                            if item.id != completed.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    } header: {
                        SectionHeader(title: "已完成")
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let onToggle: (ReminderItem) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Toggle circle
            Button { onToggle(item) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color(cgColor: item.calendarColor), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if item.isCompleted {
                        Circle()
                            .fill(Color(cgColor: item.calendarColor))
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(2)

                if let due = item.dueDate {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(due, style: .relative)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(overdue(due) && !item.isCompleted ? .red : .secondary)
                }

                if item.priority > 0 {
                    priorityBadge(item.priority)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private func overdue(_ date: Date) -> Bool { date < Date() }

    @ViewBuilder
    private func priorityBadge(_ p: Int) -> some View {
        let (label, color): (String, Color) = p <= 1 ? ("高优先级", .red) :
                                               p <= 5 ? ("中优先级", .orange) : ("低优先级", .blue)
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Shared helpers

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }
}

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }
}

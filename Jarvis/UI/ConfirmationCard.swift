import SwiftUI
import EventKit

struct ConfirmationCard: View {
    let result: RecognitionResult
    let onDismiss: () -> Void
    let onSuccess: () -> Void

    @State private var selectedLocation: LocationResult?
    @State private var showLocationPicker = false
    @State private var isWriting = false
    @State private var writeError: String?
    @State private var didSucceed = false

    private var isCalendar: Bool { result.eventType == .calendar }

    var body: some View {
        ZStack {
            if showLocationPicker, let kw = result.location {
                LocationPicker(
                    keyword: kw,
                    onSelect: { loc in
                        selectedLocation = loc
                        showLocationPicker = false
                    },
                    onCancel: { showLocationPicker = false }
                )
            } else {
                cardContent
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: true, vertical: true)
        .task(id: result.location) { await resolveLocationIfNeeded() }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                Image(systemName: isCalendar ? "calendar" : "checkmark.circle")
                    .foregroundColor(.accentColor)

                Text(isCalendar ? "日程识别结果" : "提醒事项识别结果")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            VStack(spacing: 0) {
                if let title = result.title {
                    FieldRow(key: "标题", value: title)
                }

                if isCalendar {
                    if let start = result.startTime {
                        FieldRow(key: "开始", value: formatDate(start))
                    }
                    if let end = result.endTime {
                        FieldRow(key: "结束", value: formatDate(end))
                    }
                } else {
                    if let due = result.dueDate {
                        let timeStr = result.dueTime ?? ""
                        let dateStr = formatDate(due, timeOverride: timeStr.isEmpty ? nil : timeStr)
                        FieldRow(key: "截止", value: dateStr)
                    }
                }

                if let loc = result.location {
                    HStack {
                        FieldRow(
                            key: "地点",
                            value: selectedLocation?.name ?? loc
                        )
                        if selectedLocation != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                        }
                        Button("更改") { showLocationPicker = true }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                }

                if let notes = result.notes {
                    FieldRow(key: "备注", value: notes)
                }
                if let url = result.url {
                    FieldRow(key: "链接", value: url.absoluteString)
                }
            }
            .padding(.vertical, 4)

            if let err = writeError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Button(isCalendar ? "✓ 写入日历" : "✓ 写入提醒") {
                    Task { await writeToSystem() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWriting)

                if isWriting {
                    ProgressView().scaleEffect(0.7)
                }

                Spacer()

                Button("丢弃") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private func writeToSystem() async {
        isWriting = true
        writeError = nil
        do {
            rememberLocationIfNeeded()
            switch result {
            case .calendar(let event):
                try await EventKitTool.shared.createEvent(result: event, selectedLocation: selectedLocation)
            case .reminder(let reminder):
                try await EventKitTool.shared.createReminder(result: reminder, selectedLocation: selectedLocation)
            case .none, .error:
                break
            }
            onSuccess()
        } catch {
            writeError = error.localizedDescription
        }
        isWriting = false
    }

    private func resolveLocationIfNeeded() async {
        guard selectedLocation == nil, let keyword = result.location, !keyword.isEmpty else { return }
        if let remembered = LocationMemoryStore.lookup(keyword: keyword) {
            selectedLocation = remembered
            return
        }
        let matches = await MapKitTool.search(keyword: keyword)
        selectedLocation = matches.first
    }

    private func rememberLocationIfNeeded() {
        guard let keyword = result.location, let selectedLocation else { return }
        LocationMemoryStore.save(keyword: keyword, result: selectedLocation)
    }

    private func formatDate(_ date: Date, timeOverride: String? = nil) -> String {
        let f = DateFormatter()
        if let t = timeOverride {
            f.dateFormat = "M月d日"
            return f.string(from: date) + " \(t)"
        }
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    private func priorityLabel(_ p: String) -> String {
        switch p {
        case "high": return "高 🔴"
        case "medium": return "中 🟡"
        default: return p
        }
    }
}

private struct FieldRow: View {
    let key: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(key)
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                    .frame(width: 36, alignment: .leading)
                Text(value)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider()
        }
    }
}

import SwiftUI
import EventKit

struct IslandCapsuleView: View {
    let isExpanded: Bool
    let isCapturing: Bool
    let isSuccess: Bool
    let pendingResult: RecognitionResult?
    let notchHeight: CGFloat
    let onCapture: () -> Void
    let onTaskList: () -> Void
    let onSettings: () -> Void
    let onConfirmSuccess: () -> Void
    let onConfirmDismiss: () -> Void

    @ObservedObject private var configStore = APIConfigStore.shared

    var body: some View {
        GeometryReader { geo in
            if isExpanded || isCapturing || isSuccess || pendingResult != nil {
                ZStack(alignment: .top) {
                    NotchShape(topRadius: 10, bottomRadius: 20)
                        .fill(Color.black)
                        .frame(width: geo.size.width, height: geo.size.height)

                    VStack(spacing: 0) {
                        Color.clear.frame(height: notchHeight)
                        Group {
                            if isCapturing {
                                capturingContent
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            } else if isSuccess {
                                successContent
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            } else if let result = pendingResult {
                                ConfirmationInlineView(
                                    result: result,
                                    onDismiss: onConfirmDismiss,
                                    onSuccess: onConfirmSuccess
                                )
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else {
                                expandedContent
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isCapturing)
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSuccess)
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: pendingResult == nil)
                        .frame(height: geo.size.height - notchHeight)
                    }
                }
            }
        }
    }

    private var expandedContent: some View {
        HStack(spacing: 0) {
            CapsuleButton(icon: "camera.viewfinder", label: nil, action: onCapture)
            divider
            CapsuleButton(icon: "list.bullet", label: nil, action: onTaskList)
            divider
            ProviderIcon(providerId: configStore.activeProviderId)
                .padding(.horizontal, 10)
            divider
            SettingsMenuButton(onSettings: onSettings)
        }
        .padding(.horizontal, 4)
    }

    private var capturingContent: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.55).tint(.white)
            Text("识别中…").font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
        }
    }

    private var successContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.green)
            Text("已写入").font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 18)
    }
}

// MARK: - Inline confirmation

private struct ConfirmationInlineView: View {
    let result: RecognitionResult
    let onDismiss: () -> Void
    let onSuccess: () -> Void

    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var isWriting = false
    @State private var writeError: String?

    private var isCalendar: Bool { result.eventType == .calendar }

    init(result: RecognitionResult, onDismiss: @escaping () -> Void, onSuccess: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess
        _title = State(initialValue: result.title ?? "")
        _startTime = State(initialValue: result.startTime ?? Date())
        _endTime = State(initialValue: result.endTime ?? (result.startTime ?? Date()).addingTimeInterval(3600))
        _location = State(initialValue: result.location ?? "")
        _notes = State(initialValue: result.notes ?? "")
        _dueDate = State(initialValue: result.dueDate ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: isCalendar ? "calendar.badge.plus" : "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                Text(isCalendar ? "新日程" : "新提醒")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider().background(Color.white.opacity(0.1))

            // Fields
            VStack(spacing: 0) {
                InlineField(label: "标题") {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }

                Divider().background(Color.white.opacity(0.08))

                if isCalendar {
                    InlineField(label: "开始") {
                        DatePicker("", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .scaleEffect(0.85, anchor: .leading)
                            .frame(height: 22)
                    }
                    Divider().background(Color.white.opacity(0.08))
                    InlineField(label: "结束") {
                        DatePicker("", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .scaleEffect(0.85, anchor: .leading)
                            .frame(height: 22)
                    }
                } else {
                    InlineField(label: "截止") {
                        DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .scaleEffect(0.85, anchor: .leading)
                            .frame(height: 22)
                    }
                }

                Divider().background(Color.white.opacity(0.08))
                InlineField(label: "地点") {
                    TextField("", text: $location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }

                Divider().background(Color.white.opacity(0.08))
                InlineField(label: "备注") {
                    TextField("", text: $notes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.1))

            // Actions
            HStack(spacing: 8) {
                if let err = writeError {
                    Text(err).font(.system(size: 10)).foregroundColor(.red.opacity(0.85))
                }
                Spacer()
                if isWriting {
                    ProgressView().scaleEffect(0.6).tint(.white)
                } else {
                    Button(action: onDismiss) {
                        Text("丢弃")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)

                    Button(action: { Task { await write() } }) {
                        Text("写入")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func write() async {
        isWriting = true
        writeError = nil
        do {
            switch result {
            case .calendar(var event):
                event.title = title.isEmpty ? "新日程" : title
                event.startTime = startTime
                event.endTime = endTime
                event.location = location.isEmpty ? nil : location
                event.notes = notes.isEmpty ? nil : notes
                try await EventKitTool.shared.createEvent(result: event)
            case .reminder(var reminder):
                reminder.title = title.isEmpty ? "新提醒" : title
                reminder.dueDate = dueDate
                reminder.dueTime = formatTime(dueDate)
                reminder.location = location.isEmpty ? nil : location
                reminder.notes = notes.isEmpty ? nil : notes
                try await EventKitTool.shared.createReminder(result: reminder)
            case .none, .error:
                break
            }
            onSuccess()
        } catch {
            writeError = error.localizedDescription
            isWriting = false
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct InlineField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 28, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - Subviews

private struct CapsuleButton: View {
    let icon: String
    let label: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12))
                if let label { Text(label).font(.system(size: 12)) }
            }
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SettingsMenuButton: View {
    let onSettings: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 12))
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.12) : Color.clear))
            .onHover { isHovered = $0 }
            .onTapGesture { showNSMenu() }
    }

    private func showNSMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "模型设置", action: nil, keyEquivalent: "")
        settingsItem.target = MenuActionProxy.shared
        settingsItem.action = #selector(MenuActionProxy.handleSettings(_:))
        MenuActionProxy.shared.onSettings = onSettings
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: loc.x, y: loc.y), in: nil)
    }
}

@MainActor
private class MenuActionProxy: NSObject {
    static let shared = MenuActionProxy()
    var onSettings: (() -> Void)?
    @objc func handleSettings(_ sender: Any?) { onSettings?() }
}

private struct ProviderIcon: View {
    let providerId: String?

    var body: some View {
        let assetName = "provider_\(providerId ?? "")"
        if let img = NSImage(named: assetName) {
            Image(nsImage: img)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "cpu").font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
        }
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 8

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let tr = topRadius
        let br = min(bottomRadius, w / 2, h / 2)
        path.move(to: CGPoint(x: -tr, y: 0))
        path.addLine(to: CGPoint(x: w + tr, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: tr), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: br, y: h))
        path.addArc(center: CGPoint(x: br, y: h - br), radius: br,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tr))
        path.addQuadCurve(to: CGPoint(x: -tr, y: 0), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

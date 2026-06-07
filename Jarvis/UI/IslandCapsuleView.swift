import SwiftUI
import EventKit

struct IslandCapsuleView: View {
    let isExpanded: Bool
    let isCapturing: Bool
    let isSuccess: Bool
    let pendingResponse: AgentResponse?
    let pendingProactive: ProactiveEvent?
    let compactStatusText: String?
    let notchHeight: CGFloat
    let onCapture: () -> Void
    let onTaskList: () -> Void
    let onSettings: () -> Void
    let onOpenBatchReview: () -> Void
    let onConfirmSuccess: () -> Void
    let onConfirmDismiss: () -> Void

    private var panelAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.08)
    }

    private var dropdownTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.985, anchor: .top))
                .combined(with: .offset(y: -14)),
            removal: .opacity
                .combined(with: .scale(scale: 0.975, anchor: .top))
                .combined(with: .offset(y: -18))
        )
    }

    var body: some View {
        GeometryReader { geo in
            if isExpanded || isCapturing || isSuccess || pendingResponse != nil || pendingProactive != nil || compactStatusText != nil {
                ZStack(alignment: .top) {
                    NotchShape(topRadius: 10, bottomRadius: 20)
                        .fill(Color.black)
                        .frame(width: geo.size.width, height: geo.size.height)

                    if let compactStatusText, !isExpanded && !isCapturing && !isSuccess && pendingResponse == nil && pendingProactive == nil {
                        compactStatusContent(compactStatusText)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                    } else {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: notchHeight)
                            Group {
                                if isCapturing {
                                    capturingContent
                                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                } else if isSuccess {
                                    successContent
                                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                } else if let event = pendingProactive {
                                    ProactiveInlineView(
                                        event: event,
                                        onDismiss: onConfirmDismiss
                                    )
                                    .id("proactive-\(event.id)")
                                    .transition(dropdownTransition)
                                } else if let response = pendingResponse {
                                    Group {
                                        if response.type == "batch", !(response.candidates ?? []).isEmpty {
                                            BatchSummaryInlineView(
                                                response: response,
                                                onOpen: onOpenBatchReview,
                                                onDismiss: onConfirmDismiss
                                            )
                                        } else {
                                            RecognitionMessageInlineView(
                                                result: RecognitionResult.from(response),
                                                onDismiss: onConfirmDismiss
                                            )
                                        }
                                    }
                                    .id(responseIdentity(response))
                                    .transition(dropdownTransition)
                                } else {
                                    expandedContent
                                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                }
                            }
                            .animation(panelAnimation, value: isCapturing)
                            .animation(panelAnimation, value: isSuccess)
                            .animation(panelAnimation, value: pendingResponse == nil)
                            .animation(panelAnimation, value: pendingProactive == nil)
                            .animation(panelAnimation, value: compactStatusText == nil)
                            .frame(height: geo.size.height - notchHeight)
                        }
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
            ModelSwitchButton()
            divider
            IslandMoreMenuButton()
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

    private func compactStatusContent(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 18)
    }

    private func responseIdentity(_ response: AgentResponse) -> String {
        if let sessionId = response.sessionId {
            return "response-\(sessionId)-\(response.type)-\(response.candidates?.count ?? 0)"
        }
        return "response-\(response.type)-\(response.candidates?.map(\.id).joined(separator: "-") ?? "empty")"
    }
}

// MARK: - Inline confirmation

private struct RecognitionMessageInlineView: View {
    let result: RecognitionResult
    let onDismiss: () -> Void

    private var isError: Bool {
        if case .error = result { return true }
        return false
    }

    private var title: String {
        isError ? "识别失败" : "未识别到日程或提醒"
    }

    private var message: String {
        switch result {
        case .none(let reply):
            return reply ?? "截图中没有可写入的日程或任务。"
        case .error(let error):
            return error ?? "请检查模型配置或稍后重试。"
        case .calendar, .reminder:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: isError ? "exclamationmark.triangle" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(isError ? .red.opacity(0.9) : .white.opacity(0.65))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("关闭")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

private struct BatchSummaryInlineView: View {
    let response: AgentResponse
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var candidates: [RecognitionCandidate] { response.candidates ?? [] }
    private var calendarCount: Int { candidates.filter { $0.kind == "calendar" }.count }
    private var reminderCount: Int { candidates.filter { $0.kind == "reminder" }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tray.full")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                Text("识别到 \(candidates.count) 项")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 12) {
                summaryPill(icon: "calendar", text: "\(calendarCount) 日程")
                summaryPill(icon: "checkmark.circle", text: "\(reminderCount) 待办")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Spacer()
                Button(action: onOpen) {
                    Text("打开确认")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func summaryPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.76))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

private struct ProactiveInlineView: View {
    let event: ProactiveEvent
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.68))
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            Text(event.body)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text(event.primaryButton ?? "知道了")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var icon: String {
        switch event.triggerType {
        case "event_reminder": return "calendar.badge.clock"
        case "todo_followup": return "checkmark.circle"
        case "weather_alert": return "cloud.sun"
        default: return "bell"
        }
    }
}

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
    @State private var hasValidStartTime: Bool
    @State private var hasDueDate: Bool
    @State private var needsDurationSelection: Bool
    @State private var durationResolved: Bool
    @State private var showCustomDuration = false
    @State private var selectedDurationMinutes: Int?
    @State private var isWriting = false
    @State private var writeError: String?

    private var isCalendar: Bool { result.eventType == .calendar }

    init(result: RecognitionResult, onDismiss: @escaping () -> Void, onSuccess: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess
        let initialStart = result.startTime ?? Date()
        let missingDuration = result.needsDuration && result.endTime == nil
        _title = State(initialValue: result.title ?? "")
        _startTime = State(initialValue: initialStart)
        _endTime = State(initialValue: result.endTime ?? initialStart.addingTimeInterval(3600))
        _location = State(initialValue: result.location ?? "")
        _notes = State(initialValue: result.notes ?? "")
        _dueDate = State(initialValue: result.dueDate ?? Date())
        _hasValidStartTime = State(initialValue: result.startTime != nil)
        _hasDueDate = State(initialValue: result.dueDate != nil)
        _needsDurationSelection = State(initialValue: missingDuration)
        _durationResolved = State(initialValue: !missingDuration)
        _selectedDurationMinutes = State(initialValue: nil)
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
                            .onChange(of: startTime) { _ in
                                hasValidStartTime = true
                                if let minutes = selectedDurationMinutes {
                                    endTime = startTime.addingTimeInterval(TimeInterval(minutes * 60))
                                }
                            }
                    }
                    if needsDurationSelection {
                        Divider().background(Color.white.opacity(0.08))
                        InlineField(label: "持续") {
                            HStack(spacing: 5) {
                                durationButton(minutes: 30, label: "30分")
                                durationButton(minutes: 60, label: "1h")
                                durationButton(minutes: 90, label: "1.5h")
                                durationButton(minutes: 120, label: "2h")
                                Button("自定义") {
                                    showCustomDuration = true
                                    selectedDurationMinutes = nil
                                    durationResolved = true
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(showCustomDuration ? .white : .white.opacity(0.72))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(showCustomDuration ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                                )
                            }
                        }
                        Divider().background(Color.white.opacity(0.08))
                        InlineField(label: "结束") {
                            if showCustomDuration {
                                DatePicker("", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                    .scaleEffect(0.85, anchor: .leading)
                                    .frame(height: 22)
                                    .onChange(of: endTime) { _ in durationResolved = true }
                            } else {
                                Text(durationResolved ? formatDateTime(endTime) : "请选择持续时间")
                                    .font(.system(size: 12))
                                    .foregroundColor(durationResolved ? .white : .white.opacity(0.45))
                            }
                        }
                    } else {
                        Divider().background(Color.white.opacity(0.08))
                        InlineField(label: "结束") {
                            DatePicker("", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .scaleEffect(0.85, anchor: .leading)
                                .frame(height: 22)
                                .onChange(of: endTime) { _ in durationResolved = true }
                        }
                    }
                } else {
                    InlineField(label: "截止") {
                        if hasDueDate {
                            DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .scaleEffect(0.85, anchor: .leading)
                                .frame(height: 22)
                        } else {
                            HStack(spacing: 8) {
                                Text("未设置")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.45))
                                Button("添加") { hasDueDate = true }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.82))
                            }
                        }
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
                if let statusText {
                    Text(statusText).font(.system(size: 10)).foregroundColor(.red.opacity(0.85))
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
                    .disabled(!canWrite)
                    .opacity(canWrite ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var canWrite: Bool {
        if isWriting { return false }
        guard isCalendar else { return true }
        return hasValidStartTime && durationResolved && endTime > startTime
    }

    private var statusText: String? {
        if let writeError { return writeError }
        if isCalendar && !hasValidStartTime { return "缺少开始时间" }
        if isCalendar && !durationResolved { return "请选择持续时间" }
        if isCalendar && endTime <= startTime { return "结束需晚于开始" }
        return nil
    }

    private func write() async {
        isWriting = true
        writeError = nil
        do {
            switch result {
            case .calendar(var event):
                guard hasValidStartTime else {
                    writeError = "缺少开始时间"
                    isWriting = false
                    return
                }
                guard durationResolved else {
                    writeError = "请选择持续时间"
                    isWriting = false
                    return
                }
                guard endTime > startTime else {
                    writeError = "结束需晚于开始"
                    isWriting = false
                    return
                }
                event.title = title.isEmpty ? "新日程" : title
                event.startTime = startTime
                event.endTime = endTime
                event.location = location.isEmpty ? nil : location
                event.notes = notes.isEmpty ? nil : notes
                try await EventKitTool.shared.createEvent(result: event)
            case .reminder(var reminder):
                reminder.title = title.isEmpty ? "新提醒" : title
                reminder.dueDate = hasDueDate ? dueDate : nil
                reminder.dueTime = hasDueDate ? formatTime(dueDate) : nil
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

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func selectDuration(_ minutes: Int) {
        selectedDurationMinutes = minutes
        showCustomDuration = false
        durationResolved = true
        endTime = startTime.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func durationButton(minutes: Int, label: String) -> some View {
        Button(label) { selectDuration(minutes) }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(selectedDurationMinutes == minutes ? .white : .white.opacity(0.72))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selectedDurationMinutes == minutes ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
            )
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

private struct ModelSwitchButton: View {
    @ObservedObject private var configStore = APIConfigStore.shared
    @State private var isHovered = false
    @State private var isLoading = false

    var body: some View {
        Button {
            showModelMenu()
        } label: {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.white)
                        .frame(width: 16, height: 16)
                } else {
                    ProviderIcon(providerId: configStore.activeProviderId)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
        .help("切换模型")
        .onHover { isHovered = $0 }
    }

    private func showModelMenu() {
        guard !isLoading else { return }
        let origin = NSEvent.mouseLocation
        isLoading = true
        Task {
            do {
                let response = try await GatewayClient.shared.getAvailableModels()
                let items = menuItems(from: response)
                await MainActor.run {
                    isLoading = false
                    IslandDropdownMenu.show(items: items, buttonOrigin: origin, width: 380)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    IslandDropdownMenu.show(
                        items: [
                            IslandDropdownMenu.Item(
                                title: "无法加载模型",
                                subtitle: error.localizedDescription,
                                systemImage: "exclamationmark.triangle"
                            ) {}
                        ],
                        buttonOrigin: origin,
                        width: 380
                    )
                }
            }
        }
    }

    private func menuItems(from response: AvailableModelsResponse) -> [IslandDropdownMenu.Item] {
        guard !response.sources.isEmpty else {
            return [
                IslandDropdownMenu.Item(
                    title: "暂无可切换模型",
                    subtitle: "请在菜单栏配置 API 或端侧模型",
                    systemImage: "exclamationmark.circle"
                ) {}
            ]
        }
        let activeId = response.active?.id
        return response.sources.map { source in
            IslandDropdownMenu.Item(
                title: source.modelId,
                subtitle: sourceSubtitle(source),
                systemImage: source.isLocal ? "memorychip" : "network",
                isSelected: source.id == activeId
            ) {
                Task { await activate(source) }
            }
        }
    }

    private func sourceSubtitle(_ source: ModelSource) -> String {
        let provider = source.providerDisplayName ?? PROVIDER_DISPLAY_NAMES[source.providerId ?? ""] ?? source.providerId ?? source.source
        if source.isLocal {
            return "\(provider) · 本地 OCR 文本"
        }
        return "\(provider) · \(source.supportsVision == true ? "截图视觉" : "OCR 文本")"
    }

    private func activate(_ source: ModelSource) async {
        do {
            try await GatewayClient.shared.activateModel(
                ActivateModelRequest(
                    source: source.source,
                    modelId: source.modelId,
                    providerId: source.providerId
                )
            )
            await APIConfigStore.shared.loadFromGateway()
        } catch {
            let origin = NSEvent.mouseLocation
            await MainActor.run {
                IslandDropdownMenu.show(
                    items: [
                        IslandDropdownMenu.Item(
                            title: "切换失败",
                            subtitle: error.localizedDescription,
                            systemImage: "exclamationmark.triangle"
                        ) {}
                    ],
                    buttonOrigin: origin,
                    width: 380
                )
            }
        }
    }
}

private struct IslandMoreMenuButton: View {
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.12) : Color.clear))
            .onHover { isHovered = $0 }
            .onTapGesture { showNSMenu() }
            .help("更多")
    }

    private func showNSMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: loc.x, y: loc.y), in: nil)
    }
}

private struct ProviderIcon: View {
    let providerId: String?

    var body: some View {
        if providerId == "mlx_local" {
            Image(systemName: "memorychip")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
        } else {
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

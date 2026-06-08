import Foundation
import SwiftUI

struct AssistantChatPanel: View {
    let onClose: () -> Void

    @State private var sessionID: String?
    @State private var messages: [AssistantChatMessage] = [
        AssistantChatMessage(
            role: .assistant,
            text: "我是 Jarvis，可以和我聊天，写入日程/待办/备忘录，写入你的日程/待办偏好。"
        )
    ]
    @State private var draft = ""
    @State private var isSending = false
    @State private var inFlightTask: Task<Void, Never>?
    @State private var inFlightRequestID: UUID?
    @State private var inFlightPrompt: String?
    @State private var pendingCandidate: RecognitionCandidate?
    @State private var pendingAgentSessionID: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            messageList
            Divider().opacity(0.5)
            inputBar
        }
        .frame(width: 420, height: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
        .onAppear {
            inputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisAssistantChatAppendMessage)) { notification in
            guard let text = notification.object as? String, !text.isEmpty else { return }
            messages.append(AssistantChatMessage(role: .assistant, text: text))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Jarvis")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { message in
                        AssistantMessageBubble(
                            message: message,
                            onConfirm: { confirmOperation(message.id) },
                            onCancel: { cancelOperation(message.id) }
                        )
                        .id(message.id)
                    }
                    if isSending {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("思考中，点击停止可中断")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .id("sending")
                    }
                }
                .padding(.vertical, 14)
                .textSelection(.enabled)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isSending) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit {
                    if !isSending {
                        send()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button(action: {
                if isSending {
                    stopCurrentResponse()
                } else {
                    send()
                }
            }) {
                Image(systemName: isSending ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSending ? .red : .blue)
            .disabled(!isSending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(isSending ? "停止生成" : "发送")
        }
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let requestID = UUID()
        draft = ""
        messages.append(AssistantChatMessage(role: .user, text: text))
        isSending = true
        inFlightRequestID = requestID
        inFlightPrompt = text

        inFlightTask = Task {
            do {
                if let pendingCandidate, let pendingAgentSessionID {
                    let response = try await GatewayClient.shared.chat(
                        ChatRequest(
                            message: text,
                            inputMode: "user_text",
                            sessionId: pendingAgentSessionID,
                            selectedCandidateIds: [pendingCandidate.id]
                        )
                    )
                    guard await isCurrentInFlight(requestID) else { return }
                    await handleAgentResponse(response)
                } else {
                    let response = try await GatewayClient.shared.assistantChat(
                        AssistantChatRequest(message: text, sessionId: sessionID)
                    )
                    guard await isCurrentInFlight(requestID) else { return }
                    await handle(response)
                }
                await clearInFlightIfCurrent(requestID)
            } catch {
                if isCancellationError(error) {
                    await clearInFlightIfCurrent(requestID)
                    return
                }
                await MainActor.run {
                    guard inFlightRequestID == requestID else { return }
                    messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
                    clearInFlight()
                }
            }
        }
    }

    @MainActor
    private func stopCurrentResponse() {
        guard isSending else { return }
        inFlightTask?.cancel()
        let prompt = inFlightPrompt
        clearInFlight()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let prompt {
            draft = prompt
        }
        messages.append(AssistantChatMessage(role: .assistant, text: "已停止生成，可以修改后重新发送。"))
    }

    @MainActor
    private func isCurrentInFlight(_ requestID: UUID) -> Bool {
        !Task.isCancelled && inFlightRequestID == requestID
    }

    @MainActor
    private func clearInFlightIfCurrent(_ requestID: UUID) {
        guard inFlightRequestID == requestID else { return }
        clearInFlight()
    }

    @MainActor
    private func clearInFlight() {
        inFlightTask = nil
        inFlightRequestID = nil
        inFlightPrompt = nil
        isSending = false
        inputFocused = true
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    @MainActor
    private func handle(_ response: AssistantChatResponse) async {
        guard !Task.isCancelled else { return }
        sessionID = response.sessionId

        switch response.action {
        case "review_candidates":
            if let agentResponse = response.agentResponse {
                await handleAgentResponse(agentResponse, fallbackReply: response.reply)
            } else {
                messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
            }
        case "list_items":
            if let plan = response.actionPlan {
                await executeList(plan)
            } else {
                messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
            }
        case "confirm_operation":
            if let plan = response.actionPlan {
                await prepareConfirmation(plan, fallbackReply: response.reply)
            } else {
                messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
            }
        case "execute_operation":
            if let plan = response.actionPlan {
                await executeOperation(plan, fallbackReply: response.reply)
            } else {
                messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
            }
        case "execute_note":
            if let plan = response.actionPlan {
                await executeNote(plan, fallbackReply: response.reply)
            } else {
                messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
            }
        default:
            messages.append(AssistantChatMessage(role: .assistant, text: response.reply))
        }

        clearInFlight()
    }

    @MainActor
    private func handleAgentResponse(_ agentResponse: AgentResponse, fallbackReply: String? = nil) async {
        guard !Task.isCancelled else { return }
        pendingCandidate = nil
        pendingAgentSessionID = nil

        if await tryAutoWriteSingleCandidate(agentResponse) {
            clearInFlight()
            return
        }

        guard agentResponse.type == "batch",
              let candidates = agentResponse.candidates,
              !candidates.isEmpty else {
            messages.append(AssistantChatMessage(
                role: .assistant,
                text: agentResponse.reply ?? agentResponse.error ?? fallbackReply ?? "没有识别到可写入的日程或待办。"
            ))
            clearInFlight()
            return
        }

        if candidates.count == 1, let candidate = candidates.first {
            if needsChatFollowup(candidate) {
                pendingCandidate = candidate
                pendingAgentSessionID = agentResponse.sessionId
                messages.append(AssistantChatMessage(role: .assistant, text: followupPrompt(for: candidate)))
                clearInFlight()
                return
            }

            messages.append(AssistantChatMessage(role: .assistant, text: candidateSummary(candidate)))
            clearInFlight()
            return
        }

        messages.append(AssistantChatMessage(role: .assistant, text: multiCandidateSummary(candidates)))
        clearInFlight()
    }

    @MainActor
    private func tryAutoWriteSingleCandidate(_ agentResponse: AgentResponse) async -> Bool {
        guard !Task.isCancelled else { return true }
        guard agentResponse.type == "batch",
              let candidates = agentResponse.candidates,
              candidates.count == 1,
              var candidate = candidates.first,
              (candidate.status ?? "ready") == "ready",
              (candidate.missingFields?.isEmpty ?? true) else {
            return false
        }

        do {
            switch RecognitionResult.from(candidate) {
            case .calendar(let result):
                guard let start = result.startTime else { return false }
                let end = result.endTime ?? start.addingTimeInterval(3600)
                try Task.checkCancellation()
                let conflicts = try await EventKitTool.shared.checkConflicts(start: start, end: end)
                try Task.checkCancellation()
                if !conflicts.isEmpty {
                    candidate.conflicts = conflicts
                    candidate.status = "conflict"
                    messages.append(AssistantChatMessage(role: .assistant, text: conflictSummary(candidate: candidate, conflicts: conflicts)))
                    return true
                }
                try Task.checkCancellation()
                let createdEvent = try await EventKitTool.shared.createEvent(result: result)
                try Task.checkCancellation()
                await sendAutoWriteFeedback(candidate, agentSessionID: agentResponse.sessionId)
                TaskListStore.shared.reload()
                messages.append(AssistantChatMessage(role: .assistant, text: autoWriteSummary(candidate: candidate, result: .calendar(result), createdEvent: createdEvent)))
                return true
            case .reminder(let result):
                try Task.checkCancellation()
                try await EventKitTool.shared.createReminder(result: result)
                try Task.checkCancellation()
                await sendAutoWriteFeedback(candidate, agentSessionID: agentResponse.sessionId)
                TaskListStore.shared.reload()
                messages.append(AssistantChatMessage(role: .assistant, text: autoWriteSummary(candidate: candidate, result: .reminder(result))))
                return true
            case .none, .error:
                return false
            }
        } catch {
            if isCancellationError(error) {
                return true
            }
            messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
            return true
        }
    }

    private func needsChatFollowup(_ candidate: RecognitionCandidate) -> Bool {
        let status = candidate.status ?? "ready"
        return status == "needs_input" || !(candidate.missingFields?.isEmpty ?? true)
    }

    private func followupPrompt(for candidate: RecognitionCandidate) -> String {
        if let question = candidate.clarificationQuestion, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return question
        }
        let title = candidate.calendar?.title ?? candidate.reminder?.title ?? "这项"
        let missing = candidate.missingFields ?? []
        if missing.contains("time") {
            return "\(title) 还缺具体时间，请直接告诉我时间。"
        }
        if missing.contains("duration") {
            return "\(title) 还缺持续时长，请直接告诉我大概多久。"
        }
        if missing.contains("location") {
            return "\(title) 还缺地点，请直接告诉我地点。"
        }
        return "\(title) 还需要补充信息，请直接告诉我。"
    }

    private func candidateSummary(_ candidate: RecognitionCandidate) -> String {
        let title = candidate.calendar?.title ?? candidate.reminder?.title ?? "未命名"
        let status = candidate.status ?? "ready"
        if status == "conflict" {
            return "发现「\(title)」可能有冲突，请换个时间或告诉我仍然写入。"
        }
        return "我识别到「\(title)」，但还不能直接写入。请补充更多信息。"
    }

    private func multiCandidateSummary(_ candidates: [RecognitionCandidate]) -> String {
        let lines = candidates.prefix(6).enumerated().map { index, candidate in
            let icon = candidate.kind == "calendar" ? "🗓️" : "📋"
            let title = candidate.calendar?.title ?? candidate.reminder?.title ?? "未命名"
            return "\(index + 1). \(icon) \(title)"
        }
        let suffix = candidates.count > 6 ? "\n还有 \(candidates.count - 6) 项未显示。" : ""
        return "我识别到 \(candidates.count) 项：\n" + lines.joined(separator: "\n") + suffix + "\n请一次只处理其中一项，或补充你想先写入哪一项。"
    }

    private func conflictSummary(candidate: RecognitionCandidate, conflicts: [ConflictInfo]) -> String {
        let title = candidate.calendar?.title ?? candidate.reminder?.title ?? "这项日程"
        let lines = conflicts.prefix(3).map { conflict in
            "• \(conflict.title) \(formatDateTime(conflict.startTime))-\(formatDateTime(conflict.endTime))"
        }
        return "发现「\(title)」和已有日程冲突：\n" + lines.joined(separator: "\n") + "\n请换个时间后再告诉我。"
    }

    private func sendAutoWriteFeedback(_ candidate: RecognitionCandidate, agentSessionID: String?) async {
        var finalCandidate = candidate
        finalCandidate.status = "written"
        let title = finalCandidate.calendar?.title ?? finalCandidate.reminder?.title
        let req = MemoryFeedbackRequest(
            action: "written",
            sessionId: agentSessionID ?? sessionID,
            candidateId: finalCandidate.id,
            candidateKind: finalCandidate.kind,
            title: title,
            status: "written",
            modified: false,
            note: "assistant_chat_auto_write",
            finalCandidate: finalCandidate
        )
        try? await GatewayClient.shared.memoryFeedback(req)
    }

    private func autoWriteSummary(candidate: RecognitionCandidate, result: RecognitionResult, createdEvent: CalendarEventSnapshot? = nil) -> String {
        switch result {
        case .calendar(let event):
            var parts = ["已写入日程：\(event.title)", formatDateTime(event.startTime)]
            if let calendarName = createdEvent?.calendarName, !calendarName.isEmpty {
                parts.append("日历：\(calendarName)")
            }
            return parts.joined(separator: "，") + "。"
        case .reminder(let reminder):
            var parts = ["已写入提醒事项：\(reminder.title)"]
            if let due = reminder.dueDate {
                parts.append(formatReminderDateTime(due, dueTime: reminder.dueTime))
            }
            if let alert = reminder.alertMinutesBeforeDue {
                parts.append(alert == 0 ? "准时提醒" : "提前 \(alert) 分钟提醒")
            }
            return parts.joined(separator: "，") + "。"
        case .none, .error:
            return fallbackCandidateSummary(candidate)
        }
    }

    private func fallbackCandidateSummary(_ candidate: RecognitionCandidate) -> String {
        let title = candidate.calendar?.title ?? candidate.reminder?.title ?? "未命名"
        return "已写入：\(title)。"
    }

    private func formatDateTime(_ date: Date?) -> String {
        guard let date else { return "未定时间" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func formatDateTime(_ value: String) -> String {
        guard let date = RecognitionResult.parseDate(value) else { return value }
        return formatDateTime(date)
    }

    private func formatReminderDateTime(_ date: Date, dueTime: String?) -> String {
        if dueTime?.isEmpty == false {
            return formatDateTime(date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    @MainActor
    private func executeList(_ plan: AssistantActionPlan) async {
        do {
            try Task.checkCancellation()
            let items = try await findItems(for: plan)
            try Task.checkCancellation()
            messages.append(AssistantChatMessage(role: .assistant, text: listSummary(items: items, plan: plan)))
        } catch {
            if isCancellationError(error) {
                return
            }
            messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
        }
    }

    @MainActor
    private func prepareConfirmation(_ plan: AssistantActionPlan, fallbackReply: String) async {
        do {
            try Task.checkCancellation()
            let items = try await findItems(for: plan)
            try Task.checkCancellation()
            guard !items.isEmpty else {
                messages.append(AssistantChatMessage(role: .assistant, text: noMatchText(for: plan)))
                return
            }
            guard items.count <= 10 else {
                messages.append(AssistantChatMessage(role: .assistant, text: "找到 \(items.count) 项匹配结果。为了避免误操作，请再说得具体一点。"))
                return
            }
            let operation = AssistantPendingOperation(plan: plan, items: items, fallbackReply: fallbackReply)
            messages.append(AssistantChatMessage(role: .assistant, text: "", operation: operation))
        } catch {
            if isCancellationError(error) {
                return
            }
            messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
        }
    }

    @MainActor
    private func executeOperation(_ plan: AssistantActionPlan, fallbackReply: String) async {
        do {
            try Task.checkCancellation()
            let items = try await findItems(for: plan)
            try Task.checkCancellation()
            guard !items.isEmpty else {
                messages.append(AssistantChatMessage(role: .assistant, text: noMatchText(for: plan)))
                return
            }
            guard items.count == 1 else {
                messages.append(AssistantChatMessage(role: .assistant, text: "找到 \(items.count) 项匹配结果。为了避免改错，请再说得具体一点。"))
                return
            }
            guard plan.action == "update_alert", let minutes = plan.patch?.alertMinutesBefore else {
                messages.append(AssistantChatMessage(role: .assistant, text: fallbackReply))
                return
            }

            let item = items[0]
            if item.kind == "calendar" {
                try Task.checkCancellation()
                try await EventKitTool.shared.updateEventAlerts(ids: [item.rawID], minutesBeforeStart: minutes)
            } else {
                try Task.checkCancellation()
                try await EventKitTool.shared.updateReminderAlerts(ids: [item.rawID], minutesBeforeDue: minutes)
            }
            try Task.checkCancellation()
            TaskListStore.shared.reload()
            messages.append(AssistantChatMessage(
                role: .assistant,
                text: "已将\(item.kind == "calendar" ? "日程" : "待办")「\(item.title)」改为提前 \(minutes) 分钟提醒。"
            ))
        } catch {
            if isCancellationError(error) {
                return
            }
            messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
        }
    }

    @MainActor
    private func executeNote(_ plan: AssistantActionPlan, fallbackReply: String) async {
        do {
            guard let note = plan.note else {
                messages.append(AssistantChatMessage(role: .assistant, text: fallbackReply))
                return
            }
            try Task.checkCancellation()
            let title = try await NotesTool.shared.createNote(title: note.title, content: note.content)
            try Task.checkCancellation()
            messages.append(AssistantChatMessage(role: .assistant, text: "已写入备忘录：\(title)。"))
        } catch {
            if isCancellationError(error) {
                return
            }
            messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
        }
    }

    @MainActor
    private func findItems(for plan: AssistantActionPlan) async throws -> [AssistantLocalItem] {
        let target = plan.target
        let itemKind = target?.itemKind ?? "both"
        let keywords = target?.titleKeywords ?? []
        let interval = dateInterval(from: target?.dateRange)
        var items: [AssistantLocalItem] = []

        if itemKind == "calendar" || itemKind == "both" {
            let events = try await EventKitTool.shared.queryEvents(
                start: interval?.start,
                end: interval?.end,
                keywords: keywords
            )
            items.append(contentsOf: events.map(AssistantLocalItem.init(event:)))
        }

        if itemKind == "reminder" || itemKind == "both" {
            let reminders = try await EventKitTool.shared.queryReminders(
                start: interval?.start,
                end: interval?.end,
                keywords: keywords,
                includeCompleted: false
            )
            items.append(contentsOf: reminders.map(AssistantLocalItem.init(reminder:)))
        }

        if let timeOfDay = target?.timeOfDay, !timeOfDay.isEmpty {
            items = items.filter { $0.matches(timeOfDay: timeOfDay) }
        }
        if let timePeriod = target?.timePeriod, !timePeriod.isEmpty {
            items = items.filter { $0.matches(timePeriod: timePeriod) }
        }

        return items.sorted { $0.sortDate < $1.sortDate }
    }

    @MainActor
    private func confirmOperation(_ messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              let operation = messages[idx].operation,
              operation.state == .pending else { return }

        messages[idx].operation?.state = .running
        Task {
            do {
                let summary = try await perform(operation)
                await MainActor.run {
                    if let current = messages.firstIndex(where: { $0.id == messageID }) {
                        messages[current].operation?.state = .done
                    }
                    messages.append(AssistantChatMessage(role: .assistant, text: summary))
                    TaskListStore.shared.reload()
                    inputFocused = true
                }
            } catch {
                await MainActor.run {
                    if let current = messages.firstIndex(where: { $0.id == messageID }) {
                        messages[current].operation?.state = .failed
                        messages[current].operation?.error = error.localizedDescription
                    }
                    messages.append(AssistantChatMessage(role: .assistant, text: error.localizedDescription))
                    inputFocused = true
                }
            }
        }
    }

    @MainActor
    private func cancelOperation(_ messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              let operation = messages[idx].operation,
              operation.state == .pending else { return }
        messages[idx].operation?.state = .cancelled
        messages.append(AssistantChatMessage(role: .assistant, text: "已取消\(operation.actionNoun)。"))
        inputFocused = true
    }

    @MainActor
    private func perform(_ operation: AssistantPendingOperation) async throws -> String {
        let calendarIDs = operation.items.filter { $0.kind == "calendar" }.map(\.rawID)
        let reminderIDs = operation.items.filter { $0.kind == "reminder" }.map(\.rawID)

        switch operation.plan.action {
        case "delete_items":
            if !calendarIDs.isEmpty {
                try await EventKitTool.shared.deleteEvents(ids: calendarIDs)
            }
            if !reminderIDs.isEmpty {
                try await EventKitTool.shared.deleteReminders(ids: reminderIDs)
            }
            return "已删除 \(operation.items.count) 项：\(operation.items.map(\.title).joined(separator: "、"))"
        case "reschedule_item":
            guard let patch = operation.plan.patch else {
                throw AssistantChatExecutionError.missingPatch
            }
            if !calendarIDs.isEmpty {
                try await EventKitTool.shared.updateEvents(ids: calendarIDs, patch: patch)
            }
            if !reminderIDs.isEmpty {
                try await EventKitTool.shared.updateReminders(ids: reminderIDs, patch: patch)
            }
            return operation.successSummary(for: patch)
        default:
            throw AssistantChatExecutionError.unsupportedOperation
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if isSending {
                proxy.scrollTo("sending", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func dateInterval(from range: AssistantDateRange?) -> (start: Date, end: Date)? {
        guard let range, let start = parseDate(range.startDate) else { return nil }
        let end = parseDate(range.endDate) ?? Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return (start, maxDate(end, start.addingTimeInterval(86400)))
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs > rhs ? lhs : rhs
    }

    private func listSummary(items: [AssistantLocalItem], plan: AssistantActionPlan) -> String {
        guard !items.isEmpty else { return noMatchText(for: plan) }
        let label = plan.target?.dateRange?.label ?? "匹配范围内"
        let visibleItems = Array(items.prefix(12))
        let sections = groupedListSections(for: visibleItems).map { section in
            let lines = section.items.map { item in
                item.listSummary(showDate: section.showDate)
            }
            return "**\(section.title)**\n" + lines.joined(separator: "\n")
        }
        let suffix = items.count > 12 ? "\n\n还有 \(items.count - 12) 项未显示。" : ""
        return "**\(label)共有 \(items.count) 项**\n\n" + sections.joined(separator: "\n\n") + suffix
    }

    private func groupedListSections(for items: [AssistantLocalItem]) -> [(title: String, showDate: Bool, items: [AssistantLocalItem])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) ?? today.addingTimeInterval(2 * 86400)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today.addingTimeInterval(7 * 86400)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: today) ?? today.addingTimeInterval(30 * 86400)

        let groups: [(String, Bool, (AssistantLocalItem) -> Bool)] = [
            ("今天", false, { item in
                guard let date = item.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }),
            ("明天", false, { item in
                guard let date = item.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: tomorrow)
            }),
            ("一周内", true, { item in
                guard let date = item.scheduledDate else { return false }
                return date >= dayAfterTomorrow && date < weekEnd
            }),
            ("一个月内", true, { item in
                guard let date = item.scheduledDate else { return false }
                return date >= weekEnd && date < monthEnd
            }),
            ("更晚", true, { item in
                guard let date = item.scheduledDate else { return false }
                return date >= monthEnd
            }),
            ("未定时间", true, { item in
                item.scheduledDate == nil
            })
        ]

        return groups.compactMap { title, showDate, matches in
            let matched = items.filter(matches)
            guard !matched.isEmpty else { return nil }
            return (title: title, showDate: showDate, items: matched)
        }
    }

    private func noMatchText(for plan: AssistantActionPlan) -> String {
        let label = plan.target?.dateRange?.label ?? "匹配范围内"
        switch plan.target?.itemKind ?? "both" {
        case "calendar":
            return "没有找到\(label)匹配的日程。"
        case "reminder":
            return "没有找到\(label)匹配的待办。"
        default:
            return "没有找到\(label)匹配的日程或待办。"
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantChatMessage
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 42)
            }

            if let operation = message.operation {
                AssistantOperationCard(operation: operation, onConfirm: onConfirm, onCancel: onCancel)
                    .frame(maxWidth: 356, alignment: .leading)
            } else {
                messageText
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if message.role == .assistant {
                Spacer(minLength: 42)
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var messageText: some View {
        if message.role == .assistant {
            AssistantMessageText(text: message.text)
        } else {
            Text(message.text)
        }
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.blue)
            : AnyShapeStyle(Color.secondary.opacity(0.10))
    }
}

private struct AssistantMessageText: View {
    let text: String

    var body: some View {
        Text(markdownText)
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var markdownText: AttributedString {
        (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct AssistantOperationCard: View {
    let operation: AssistantPendingOperation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(operation.tint.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: operation.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(operation.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(operation.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if operation.state == .running {
                    ProgressView().controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(operation.items.prefix(5)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: item.kind == "calendar" ? "calendar" : "checkmark.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(item.kind == "calendar" ? Color.blue : Color.green)
                            .frame(width: 14)
                        Text(item.compactSummary)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                    }
                }
                if operation.items.count > 5 {
                    Text("还有 \(operation.items.count - 5) 项")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(9)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let error = operation.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                if operation.state == .done {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                } else if operation.state == .cancelled {
                    Label("已取消", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Button("取消", action: onCancel)
                        .disabled(operation.state == .running)
                    Spacer()
                    Button(operation.confirmTitle, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .disabled(operation.state == .running)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}

private struct AssistantChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var operation: AssistantPendingOperation?
}

private struct AssistantPendingOperation {
    let plan: AssistantActionPlan
    let items: [AssistantLocalItem]
    let fallbackReply: String
    var state: AssistantOperationState = .pending
    var error: String?

    var title: String {
        switch plan.action {
        case "delete_items": return "确认删除"
        case "reschedule_item": return "确认修改"
        default: return "确认操作"
        }
    }

    var actionNoun: String {
        switch plan.action {
        case "delete_items": return "删除"
        case "reschedule_item": return "修改"
        default: return "操作"
        }
    }

    var confirmTitle: String {
        switch plan.action {
        case "delete_items": return "删除"
        case "reschedule_item": return "修改"
        default: return "确认"
        }
    }

    var detail: String {
        if plan.action == "reschedule_item", let patch = plan.patch {
            if let shift = patch.shiftMinutes {
                if shift > 0 { return "将 \(items.count) 项推迟 \(durationText(abs(shift)))" }
                if shift < 0 { return "将 \(items.count) 项提前 \(durationText(abs(shift)))" }
            }
            if let time = patch.newStartTime ?? patch.newDueTime {
                return "将 \(items.count) 项改到 \(time)"
            }
            if let location = patch.location {
                return "将 \(items.count) 项地点改为 \(location)"
            }
        }
        if plan.action == "delete_items" {
            return "将删除 \(items.count) 项，删除前需要你确认"
        }
        return fallbackReply
    }

    func successSummary(for patch: AssistantOperationPatch) -> String {
        let clauses = successClauses(for: patch)

        guard let first = items.first else {
            return clauses.isEmpty ? "已完成修改。" : "已完成修改：\(clauses.joined(separator: "，"))。"
        }

        if items.count == 1 {
            if clauses.isEmpty {
                return "已修改\(first.kindNoun)「\(first.title)」。"
            }
            return "已将\(first.kindNoun)「\(first.title)」\(clauses.joined(separator: "，"))。"
        }

        let titles = titlesText
        if clauses.isEmpty {
            return "已修改 \(items.count) 项：\(titles)。"
        }
        return "已将 \(items.count) 项\(clauses.joined(separator: "，"))：\(titles)。"
    }

    var systemImage: String {
        plan.action == "delete_items" ? "trash" : "clock.arrow.circlepath"
    }

    var tint: Color {
        plan.action == "delete_items" ? .red : .blue
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    private var titlesText: String {
        let visibleTitles = items.prefix(5).map(\.title).joined(separator: "、")
        if items.count > 5 {
            return "\(visibleTitles) 等 \(items.count) 项"
        }
        return visibleTitles
    }

    private func successClauses(for patch: AssistantOperationPatch) -> [String] {
        var clauses: [String] = []

        if let shift = patch.shiftMinutes, shift != 0 {
            clauses.append(shift > 0 ? "推迟 \(durationText(abs(shift)))" : "提前 \(durationText(abs(shift)))")
        } else if let time = changedTimeText(for: patch) {
            clauses.append("改到 \(time)")
        } else if let endTime = patch.newEndTime {
            clauses.append("结束时间改为 \(Self.readableDateTime(endTime))")
        }

        if let alert = patch.alertMinutesBefore {
            clauses.append("提醒改为\(alertText(alert))")
        }

        if let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            clauses.append("标题改为「\(title)」")
        }

        if let location = patch.location {
            let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
            clauses.append(trimmed.isEmpty ? "清除地点" : "地点改为 \(trimmed)")
        }

        return clauses
    }

    private func changedTimeText(for patch: AssistantOperationPatch) -> String? {
        if patch.newDueDate != nil || patch.newDueTime != nil {
            return Self.dueDateTimeText(date: patch.newDueDate, time: patch.newDueTime ?? patch.newStartTime)
        }
        if let startTime = patch.newStartTime {
            return Self.dateTimeRangeText(start: startTime, end: patch.newEndTime)
        }
        return nil
    }

    private func alertText(_ minutes: Int) -> String {
        if minutes <= 0 {
            return "准时提醒"
        }
        return "提前 \(durationText(minutes))"
    }

    private static func dateTimeRangeText(start: String, end: String?) -> String {
        guard let end else {
            return readableDateTime(start)
        }

        if let startDate = parseDateTime(start), let endDate = parseDateTime(end) {
            let startText = "\(dayFormatter.string(from: startDate)) \(timeFormatter.string(from: startDate))"
            let endText = Calendar.current.isDate(startDate, inSameDayAs: endDate)
                ? timeFormatter.string(from: endDate)
                : "\(dayFormatter.string(from: endDate)) \(timeFormatter.string(from: endDate))"
            return "\(startText)-\(endText)"
        }

        return "\(readableDateTime(start))-\(readableDateTime(end))"
    }

    private static func dueDateTimeText(date: String?, time: String?) -> String? {
        if let date, let parsedDate = parseDateOnly(date) {
            let day = dayFormatter.string(from: parsedDate)
            guard let time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return day
            }
            return "\(day) \(readableDateTime(time))"
        }

        if let date, !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var parts = [readableDateTime(date)]
            if let time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(readableDateTime(time))
            }
            return parts.joined(separator: " ")
        }

        if let time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return readableDateTime(time)
        }

        return nil
    }

    private static func readableDateTime(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = parseDateTime(trimmed) {
            return "\(dayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
        }
        if let date = parseDateOnly(trimmed) {
            return dayFormatter.string(from: date)
        }
        let parts = trimmed.split(separator: ":")
        if parts.count >= 2, parts[0].count <= 2, parts[1].count == 2 {
            return "\(parts[0]):\(parts[1])"
        }
        return trimmed
    }

    private static func parseDateTime(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d E"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum AssistantOperationState {
    case pending
    case running
    case done
    case cancelled
    case failed
}

private struct AssistantLocalItem: Identifiable, Equatable {
    let kind: String
    let rawID: String
    let title: String
    let startTime: String?
    let endTime: String?
    let dueDate: String?
    let dueTime: String?
    let location: String?
    let containerName: String?
    let alertMinutesBefore: Int?

    var id: String { "\(kind):\(rawID)" }

    init(event: CalendarEventSnapshot) {
        kind = "calendar"
        rawID = event.id
        title = event.title
        startTime = event.startTime
        endTime = event.endTime
        dueDate = nil
        dueTime = nil
        location = event.location
        containerName = event.calendarName
        alertMinutesBefore = event.alertMinutesBeforeStart
    }

    init(reminder: ReminderSnapshot) {
        kind = "reminder"
        rawID = reminder.id
        title = reminder.title
        startTime = nil
        endTime = nil
        dueDate = reminder.dueDate
        dueTime = reminder.dueTime
        location = nil
        containerName = reminder.listName
        alertMinutesBefore = reminder.alertMinutesBeforeDue
    }

    var scheduledDate: Date? {
        if let startTime, let date = Self.parseDateTime(startTime) { return date }
        if let dueDate, let dueTime, let date = Self.parseDateTime("\(dueDate)T\(dueTime):00") { return date }
        if let dueDate, let date = Self.parseDateOnly(dueDate) { return date }
        return nil
    }

    var sortDate: Date {
        scheduledDate ?? Date.distantFuture
    }

    var kindNoun: String {
        kind == "calendar" ? "日程" : "待办"
    }

    var compactSummary: String {
        if kind == "calendar" {
            let time = Self.eventTimeText(start: startTime, end: endTime)
            return "\(time) \(title)"
        }
        let time = Self.reminderTimeText(date: dueDate, time: dueTime)
        return "\(time) \(title)"
    }

    func listSummary(showDate: Bool) -> String {
        let icon = kind == "calendar" ? "🗓️" : "📋"
        let time = kind == "calendar"
            ? Self.eventTimeText(start: startTime, end: endTime, showDate: showDate)
            : Self.reminderTimeText(date: dueDate, time: dueTime, showDate: showDate)
        return "\(icon) \(time) \(title)\(alertSummary)"
    }

    func matches(timeOfDay: String) -> Bool {
        let normalized = timeOfDay.count == 5 ? timeOfDay : String(timeOfDay.prefix(5))
        return Self.timeFormatter.string(from: sortDate) == normalized
    }

    func matches(timePeriod: String) -> Bool {
        guard let date = scheduledDate else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        switch timePeriod.lowercased() {
        case "morning":
            return hour >= 5 && hour < 12
        case "afternoon":
            return hour >= 12 && hour < 18
        case "evening":
            return hour >= 18 && hour < 24
        case "night":
            return hour < 6 || hour >= 21
        default:
            return true
        }
    }

    private var alertSummary: String {
        guard let alertMinutesBefore else { return "（无提醒）" }
        if alertMinutesBefore <= 0 { return "（准时提醒）" }
        return "（提前 \(durationText(alertMinutesBefore))提醒）"
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    private static func eventTimeText(start: String?, end: String?, showDate: Bool = true) -> String {
        guard let startDate = parseDateTime(start) else { return "未定时间" }
        let day = showDate ? "\(dayFormatter.string(from: startDate)) " : ""
        let startText = timeFormatter.string(from: startDate)
        guard let endDate = parseDateTime(end) else { return "\(day)\(startText)" }
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return "\(day)\(startText)-\(timeFormatter.string(from: endDate))"
        }
        let endDay = showDate ? "\(dayFormatter.string(from: endDate)) " : ""
        return "\(day)\(startText)-\(endDay)\(timeFormatter.string(from: endDate))"
    }

    private static func reminderTimeText(date: String?, time: String?, showDate: Bool = true) -> String {
        guard let date else { return "未设时间" }
        if let parsed = parseDateOnly(date) {
            let day = showDate ? "\(dayFormatter.string(from: parsed)) " : ""
            if let time { return "\(day)\(time)" }
            return showDate ? day.trimmingCharacters(in: .whitespaces) : "全天"
        }
        return [date, time].compactMap { $0 }.joined(separator: " ")
    }

    private static func parseDateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d E"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum AssistantChatExecutionError: Error, LocalizedError {
    case missingPatch
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .missingPatch: return "缺少要修改的时间或地点"
        case .unsupportedOperation: return "这个操作暂时不能执行"
        }
    }
}

import SwiftUI

struct BatchReviewResult {
    let action: String
    let kind: String
    let title: String

    var chatSummary: String {
        let kindText = kind == "calendar" ? "日程" : "待办"
        switch action {
        case "written":
            return "已写入\(kindText)：\(title)"
        case "replaced":
            return "已替换并写入\(kindText)：\(title)"
        case "skipped":
            return "已跳过\(kindText)：\(title)"
        default:
            return "已处理\(kindText)：\(title)"
        }
    }
}

struct BatchReviewPanel: View {
    @State private var drafts: [CandidateDraft]
    @State private var currentIndex = 0
    @State private var processingID: String?

    private let totalCount: Int
    private let sessionID: String?
    let onCandidateResolved: ((BatchReviewResult) -> Void)?
    let onClose: () -> Void

    init(
        response: AgentResponse,
        onCandidateResolved: ((BatchReviewResult) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        let initial = (response.candidates ?? []).enumerated().map { idx, candidate in
            CandidateDraft(candidate: candidate, fallbackIndex: idx + 1)
        }
        _drafts = State(initialValue: initial)
        totalCount = initial.count
        sessionID = response.sessionId
        self.onCandidateResolved = onCandidateResolved
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            deck
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.78), in: Circle())
            }
            .help("关闭")
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .frame(width: 440, height: 460, alignment: .top)
    }

    private var deck: some View {
        ZStack(alignment: .top) {
            if isComplete {
                completionView
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(deckIndices, id: \.self) { idx in
                        let depth = idx - currentIndex
                        if idx == currentIndex {
                            activeCard(at: idx)
                                .zIndex(Double(10 - depth))
                                .transition(cardTransition)
                        } else {
                            PreviewCandidateCard(draft: drafts[idx], depth: depth)
                                .allowsHitTesting(false)
                                .zIndex(Double(10 - depth))
                                .transition(cardTransition)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 28)
                .padding(.trailing, 18)
                .animation(deckAnimation, value: currentIndex)
                .animation(deckAnimation, value: drafts.map(\.status).joined(separator: "|"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func activeCard(at idx: Int) -> some View {
        CandidateDeckCard(
            draft: drafts[idx],
            progressText: "\(idx + 1)/\(max(totalCount, 1))",
            isBusy: processingID == drafts[idx].id
        ) {
            CandidateDraftEditor(
                draft: $drafts[idx],
                isBusy: processingID == drafts[idx].id,
                onSubmitFollowup: { text in
                    Task { await submitFollowup(text, for: drafts[idx].id) }
                },
                onRefreshConflicts: {
                    Task { await refreshConflicts(for: drafts[idx].id) }
                },
                onSkip: {
                    Task { await skip(drafts[idx].id) }
                },
                onWrite: {
                    Task { await checkAndWrite(id: drafts[idx].id) }
                },
                onForceWrite: {
                    Task { await forceWrite(drafts[idx].id) }
                },
                onReplaceConflicts: {
                    Task { await replaceConflicts(for: drafts[idx].id) }
                }
            )
        }
    }

    private var completionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("已完成")
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deckIndices: [Int] {
        guard currentIndex < drafts.count else { return [] }
        return Array(currentIndex..<min(drafts.count, currentIndex + 3)).reversed()
    }

    private var isComplete: Bool {
        currentIndex >= drafts.count
    }

    private var deckAnimation: Animation {
        .spring(response: 0.40, dampingFraction: 0.87, blendDuration: 0.05)
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .center))
                .combined(with: .offset(x: 28, y: 10)),
            removal: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .topLeading))
                .combined(with: .offset(x: -72, y: -10))
        )
    }
}

extension BatchReviewPanel {
    @MainActor
    private func submitFollowup(_ text: String, for id: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = drafts.firstIndex(where: { $0.id == id }), processingID == nil else { return }

        processingID = id
        drafts[idx].status = "updating"
        drafts[idx].error = nil

        let req = ChatRequest(
            message: trimmed,
            image: nil,
            inputMode: "user_text",
            sessionId: sessionID,
            formData: nil,
            userAction: nil,
            originalResult: nil,
            corrections: drafts[idx].corrections,
            selectedCandidateIds: [id]
        )

        do {
            let response = try await GatewayClient.shared.chat(req)
            guard let updated = matchingCandidate(in: response, currentID: id) else {
                drafts[idx].status = "needs_input"
                drafts[idx].error = response.error ?? "没有找到当前候选项的更新结果"
                processingID = nil
                return
            }
            drafts[idx].applyFollowup(updated)
            processingID = nil
        } catch {
            drafts[idx].status = "needs_input"
            drafts[idx].error = error.localizedDescription
            processingID = nil
        }
    }

    private func matchingCandidate(in response: AgentResponse, currentID: String) -> RecognitionCandidate? {
        let candidates = response.candidates ?? []
        if let exact = candidates.first(where: { $0.id == currentID }) {
            return exact
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    @MainActor
    private func refreshConflicts(for id: String) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        guard drafts[idx].kind == "calendar", let start = drafts[idx].startDate, let end = drafts[idx].endDate, end > start else { return }
        let conflicts = (try? await EventKitTool.shared.checkConflicts(start: start, end: end)) ?? []
        drafts[idx].conflicts = conflicts
        drafts[idx].selectedConflictIDs = []
        drafts[idx].refreshInputStatus()
    }

    @MainActor
    private func checkAndWrite(id: String) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }), processingID == nil else { return }
        guard drafts[idx].canWrite else {
            drafts[idx].status = "needs_input"
            processingID = nil
            return
        }

        processingID = id
        if drafts[idx].kind == "calendar" {
            drafts[idx].status = "checking_conflict"
            guard let start = drafts[idx].startDate, let end = drafts[idx].endDate else {
                drafts[idx].status = "needs_input"
                processingID = nil
                return
            }
            do {
                let conflicts = try await EventKitTool.shared.checkConflicts(start: start, end: end)
                if !conflicts.isEmpty && !drafts[idx].allowConflictWrite {
                    drafts[idx].conflicts = conflicts
                    drafts[idx].selectedConflictIDs = []
                    drafts[idx].status = "conflict"
                    processingID = nil
                    return
                }
            } catch {
                drafts[idx].status = "error"
                drafts[idx].error = error.localizedDescription
                processingID = nil
                return
            }
        }

        await writeCandidate(id: id)
    }

    @MainActor
    private func writeCandidate(id: String, replacing eventIDs: [String] = []) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else {
            processingID = nil
            return
        }
        guard drafts[idx].canWrite else {
            drafts[idx].status = "needs_input"
            processingID = nil
            return
        }

        processingID = id
        drafts[idx].status = eventIDs.isEmpty ? "writing" : "replacing"
        drafts[idx].error = nil

        do {
            if !eventIDs.isEmpty {
                try await EventKitTool.shared.deleteEvents(ids: eventIDs)
            }
            if drafts[idx].kind == "calendar" {
                try await EventKitTool.shared.createEvent(result: drafts[idx].calendarRecognition)
            } else {
                try await EventKitTool.shared.createReminder(result: drafts[idx].reminderRecognition)
            }
            drafts[idx].status = "written"
            await sendFeedback(for: drafts[idx], action: eventIDs.isEmpty ? "written" : "replaced")
            onCandidateResolved?(BatchReviewResult(
                action: eventIDs.isEmpty ? "written" : "replaced",
                kind: drafts[idx].kind,
                title: drafts[idx].displayTitle
            ))
            TaskListStore.shared.reload()
            try? await Task.sleep(nanoseconds: 350_000_000)
            processingID = nil
            advanceOrClose()
        } catch {
            drafts[idx].status = "error"
            drafts[idx].error = error.localizedDescription
            processingID = nil
        }
    }

    @MainActor
    private func forceWrite(_ id: String) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }), processingID == nil else { return }
        drafts[idx].allowConflictWrite = true
        drafts[idx].conflicts = []
        processingID = id
        await writeCandidate(id: id)
    }

    @MainActor
    private func replaceConflicts(for id: String) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }), processingID == nil else { return }
        let selected = Array(drafts[idx].selectedConflictIDs)
        guard !selected.isEmpty else {
            drafts[idx].error = "请选择要替换的旧行程"
            return
        }
        processingID = id
        await writeCandidate(id: id, replacing: selected)
    }

    @MainActor
    private func skip(_ id: String) async {
        guard let idx = drafts.firstIndex(where: { $0.id == id }), processingID == nil else { return }
        drafts[idx].status = "skipped"
        await sendFeedback(for: drafts[idx], action: "skipped")
        onCandidateResolved?(BatchReviewResult(
            action: "skipped",
            kind: drafts[idx].kind,
            title: drafts[idx].displayTitle
        ))
        try? await Task.sleep(nanoseconds: 140_000_000)
        advanceOrClose()
    }

    @MainActor
    private func advanceOrClose() {
        let nextIndex = min(currentIndex + 1, drafts.count)
        withAnimation(deckAnimation) {
            currentIndex = nextIndex
        }
        if nextIndex >= drafts.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                onClose()
            }
        }
    }

    private func sendFeedback(for draft: CandidateDraft, action: String, note: String? = nil) async {
        let req = MemoryFeedbackRequest(
            action: action,
            sessionId: sessionID,
            candidateId: draft.id,
            candidateKind: draft.kind,
            title: draft.title.isEmpty ? nil : draft.title,
            status: draft.status,
            modified: draft.isModified,
            note: note,
            finalCandidate: draft.finalCandidateSnapshot
        )
        try? await GatewayClient.shared.memoryFeedback(req)
    }
}

private struct CandidateDeckCard<Content: View>: View {
    let draft: CandidateDraft
    let progressText: String
    let isBusy: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(draft.tintColor.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: draft.kind == "calendar" ? "calendar" : "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(draft.tintColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.kindLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(draft.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text(progressText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(draft.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(draft.statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(draft.statusColor.opacity(0.12))
                        )
                }
                CandidateTimeOverview(draft: draft)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 13)

            Divider()

            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct CandidateTimeOverview: View {
    let draft: CandidateDraft

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(draft.primaryDateLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(draft.primaryDateIsMissing ? Color.orange : Color.primary)
                .lineLimit(1)
            Spacer()
            if let location = draft.locationLabel {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .medium))
                    Text(location)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PreviewCandidateCard: View {
    let draft: CandidateDraft
    let depth: Int

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(draft.tintColor.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: draft.kind == "calendar" ? "calendar" : "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(draft.tintColor.opacity(0.9))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.kindLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(draft.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Text(draft.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(draft.statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(draft.statusColor.opacity(0.10))
                        )
                }
                CandidateTimeOverview(draft: draft)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 13)

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: draft.needsInput ? "bubble.left.and.text.bubble.right" : "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(draft.tintColor.opacity(0.75))
                    Text(draft.needsInput ? draft.clarificationPrompt : draft.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(1)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 210, height: 10)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(width: 145, height: 10)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 318, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
        .scaleEffect(max(0.88, 1 - CGFloat(depth) * 0.045), anchor: .topLeading)
        .offset(x: CGFloat(depth) * 15, y: CGFloat(depth) * 18)
        .opacity(max(0.50, 1 - CGFloat(depth) * 0.22))
    }
}

private struct CandidateDraftEditor: View {
    @Binding var draft: CandidateDraft
    let isBusy: Bool
    let onSubmitFollowup: (String) -> Void
    let onRefreshConflicts: () -> Void
    let onSkip: () -> Void
    let onWrite: () -> Void
    let onForceWrite: () -> Void
    let onReplaceConflicts: () -> Void

    @State private var followupText = ""
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.showsConversationBox {
                followupBox
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            CandidateInfoSummary(draft: draft)

            detailsDisclosure

            if !draft.conflicts.isEmpty {
                conflictBox
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let error = draft.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(14)
    }

    private var detailsDisclosure: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            ScrollView {
                fields
                    .padding(.top, 8)
            }
            .frame(maxHeight: 240)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                Text("编辑详情")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .disabled(isBusy)
    }

    private var fields: some View {
        VStack(spacing: 9) {
            labeled("标题") {
                TextField("标题", text: Binding(
                    get: { draft.title },
                    set: {
                        draft.title = $0
                        if !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.resolveMissing("title")
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)
            }

            if draft.kind == "calendar" {
                DateTimeEditRow(
                    title: "开始时间",
                    systemImage: "calendar.badge.clock",
                    date: Binding(
                        get: { draft.startDate },
                        set: { draft.startDate = $0 }
                    ),
                    isMissing: draft.primaryTimeIsMissing,
                    placeholder: "选择开始时间",
                    disabled: isBusy,
                    fallbackDate: { Date() },
                    onChange: {
                        draft.resolveMissing("time")
                        onRefreshConflicts()
                    }
                )
                DateTimeEditRow(
                    title: "结束时间",
                    systemImage: "timer",
                    date: Binding(
                        get: { draft.endDate },
                        set: { draft.endDate = $0 }
                    ),
                    isMissing: draft.endTimeIsMissing,
                    placeholder: "选择结束时间",
                    disabled: isBusy,
                    fallbackDate: { (draft.startDate ?? Date()).addingTimeInterval(3600) },
                    onChange: {
                        draft.resolveMissing("duration")
                        onRefreshConflicts()
                    }
                )
            } else {
                Toggle("设置截止时间", isOn: Binding(
                    get: { draft.hasDueDate },
                    set: {
                        draft.hasDueDate = $0
                        if $0 && draft.dueDate == nil {
                            draft.dueDate = Date()
                            draft.dueTime = draft.formatTime(Date())
                            draft.resolveMissing("time")
                        } else if !$0 {
                            draft.dueDate = nil
                            draft.dueTime = nil
                        }
                    }
                ))
                .disabled(isBusy)
                if draft.hasDueDate {
                    DateTimeEditRow(
                        title: "提醒时间",
                        systemImage: "bell.badge",
                        date: Binding(
                            get: { draft.dueDate },
                            set: {
                                draft.dueDate = $0
                                draft.dueTime = draft.formatTime($0)
                            }
                        ),
                        isMissing: draft.primaryTimeIsMissing,
                        placeholder: "选择提醒时间",
                        disabled: isBusy,
                        fallbackDate: { Date() },
                        onChange: {
                            if let dueDate = draft.dueDate {
                                draft.dueTime = draft.formatTime(dueDate)
                            }
                            draft.resolveMissing("time")
                        }
                    )
                }
            }

            labeled("地点") {
                TextField("地点", text: Binding(
                    get: { draft.location },
                    set: {
                        draft.location = $0
                        if !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.resolveMissing("location")
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)
            }
        }
    }

    private var followupBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.conversationPrompt)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            HStack(spacing: 8) {
                TextField("", text: $followupText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
                    .onSubmit { submitFollowup() }
                Button(action: submitFollowup) {
                    Image(systemName: isBusy ? "hourglass" : "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || followupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var conflictBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("发现日程冲突")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            ForEach(draft.conflicts, id: \.id) { conflict in
                Toggle(isOn: Binding(
                    get: { draft.selectedConflictIDs.contains(conflict.id) },
                    set: { selected in
                        if selected {
                            draft.selectedConflictIDs.insert(conflict.id)
                        } else {
                            draft.selectedConflictIDs.remove(conflict.id)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text("\(format(conflict.startTime)) - \(format(conflict.endTime))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(isBusy)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("跳过", action: onSkip)
                .disabled(isBusy)
            Spacer()
            if draft.status == "conflict" {
                Button("改时间") {
                    draft.status = "needs_input"
                    draft.missingFields.appendIfMissing("time")
                    draft.clarificationQuestion = ""
                }
                .disabled(isBusy)
                Button("仍然写入", action: onForceWrite)
                    .disabled(isBusy)
                Button("替换旧行程", action: onReplaceConflicts)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || draft.selectedConflictIDs.isEmpty)
            } else if draft.isPassive {
                Text(draft.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(draft.statusColor)
            } else if isBusy {
                Text(draft.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(draft.statusColor)
            } else if draft.canWrite {
                Button("写入", action: onWrite)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            } else {
                Text("等待补充")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func submitFollowup() {
        let value = followupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        followupText = ""
        onSubmitFollowup(value)
    }

    private func format(_ value: String) -> String {
        guard let date = RecognitionResult.parseDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

private struct CandidateInfoSummary: View {
    let draft: CandidateDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: row.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(row.isPrimary ? draft.tintColor : Color.secondary)
                        .frame(width: 16)
                    Text(row.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: row.isPrimary ? 12 : 11, weight: row.isPrimary ? .semibold : .medium))
                        .foregroundStyle(row.isMuted ? Color.secondary : Color.primary)
                        .lineLimit(row.allowsWrap ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private var rows: [SummaryInfoRow] {
        var output: [SummaryInfoRow] = []
        if draft.kind == "calendar" {
            output.append(SummaryInfoRow(
                systemImage: "clock",
                label: "时间",
                value: draft.preferenceMarked(draft.calendarTimeSummary, fields: ["calendar.end_time"]),
                isPrimary: true,
                isMuted: draft.primaryTimeIsMissing || draft.endTimeIsMissing
            ))
            if let location = draft.locationLabel {
                output.append(SummaryInfoRow(systemImage: "mappin.and.ellipse", label: "地点", value: location))
            }
            output.append(SummaryInfoRow(
                systemImage: "bell",
                label: "提醒",
                value: draft.preferenceMarked(draft.calendarAlertLabel, fields: ["calendar.alert_minutes_before_start"])
            ))
        } else {
            output.append(SummaryInfoRow(
                systemImage: "bell.badge",
                label: "提醒",
                value: draft.preferenceMarked(
                    draft.reminderDueSummary,
                    fields: ["reminder.due_time", "reminder.alert_minutes_before_due"]
                ),
                isPrimary: true,
                isMuted: draft.primaryTimeIsMissing
            ))
            if let location = draft.locationLabel {
                output.append(SummaryInfoRow(systemImage: "mappin.and.ellipse", label: "地点", value: location))
            }
            output.append(SummaryInfoRow(
                systemImage: "list.bullet",
                label: "列表",
                value: draft.preferenceMarked(draft.listName, fields: ["reminder.list_name"])
            ))
            if draft.priority != "none" || draft.flagged {
                output.append(SummaryInfoRow(systemImage: "flag", label: "标记", value: draft.reminderFlagLabel))
            }
        }

        if let recurrence = draft.recurrenceSummary {
            output.append(SummaryInfoRow(systemImage: "repeat", label: "重复", value: recurrence))
        }
        if let notes = draft.notesSummary {
            output.append(SummaryInfoRow(systemImage: "note.text", label: "备注", value: notes, allowsWrap: true))
        }
        if let url = draft.urlSummary {
            output.append(SummaryInfoRow(systemImage: "link", label: "链接", value: url, allowsWrap: true))
        }
        return output
    }
}

private struct SummaryInfoRow: Identifiable {
    let id = UUID()
    let systemImage: String
    let label: String
    let value: String
    var isPrimary = false
    var isMuted = false
    var allowsWrap = false
}

private struct DateTimeEditRow: View {
    let title: String
    let systemImage: String
    @Binding var date: Date?
    let isMissing: Bool
    let placeholder: String
    let disabled: Bool
    let fallbackDate: () -> Date
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if isMissing {
                    Text("待补充")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
            }

            if date == nil {
                Button {
                    date = fallbackDate()
                    onChange()
                } label: {
                    HStack(spacing: 6) {
                        Text(placeholder)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(isMissing ? Color.orange : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            } else {
                HStack(spacing: 8) {
                    DatePicker("", selection: dateBinding, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.small)
                    Divider()
                        .frame(height: 20)
                    DatePicker("", selection: dateBinding, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(disabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isMissing ? Color.orange.opacity(0.07) : Color.secondary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isMissing ? Color.orange.opacity(0.36) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        isMissing ? .orange : .blue
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date ?? fallbackDate() },
            set: {
                date = $0
                onChange()
            }
        )
    }
}

private struct CandidateDraft: Identifiable {
    let id: String
    let kind: String
    var title: String
    var notes: String
    var location: String
    var startDate: Date?
    var endDate: Date?
    var dueDate: Date?
    var dueTime: String?
    var hasDueDate: Bool
    var recurrence: RecurrenceRule?
    var alertMinutesBeforeStart: Int
    var alertMinutesBeforeDue: Int?
    var calendarName: String?
    var listName: String
    var priority: String
    var flagged: Bool
    var url: URL?
    var appliedPreferences: [AppliedPreference]
    var missingFields: [String]
    var clarificationQuestion: String
    var conflicts: [ConflictInfo]
    var selectedConflictIDs: Set<String> = []
    var status: String
    var allowConflictWrite = false
    var error: String?
    var originalFingerprint = ""

    init(candidate: RecognitionCandidate, fallbackIndex: Int) {
        id = candidate.id
        kind = candidate.kind
        if candidate.kind == "calendar", let payload = candidate.calendar {
            title = payload.title ?? ""
            notes = payload.notes ?? ""
            location = payload.location ?? ""
            startDate = RecognitionResult.parseDate(payload.startTime)
            let start = startDate ?? Date()
            endDate = RecognitionResult.parseDate(payload.endTime) ?? (payload.needsDuration == true ? nil : start.addingTimeInterval(3600))
            dueDate = nil
            dueTime = nil
            hasDueDate = false
            recurrence = payload.recurrence.map(RecurrenceRule.from)
            alertMinutesBeforeStart = payload.alertMinutesBeforeStart ?? 10
            alertMinutesBeforeDue = nil
            calendarName = payload.calendarName
            listName = "提醒事项"
            priority = "none"
            flagged = false
            url = payload.url.flatMap(URL.init(string:))
        } else {
            let payload = candidate.reminder
            title = payload?.title ?? ""
            notes = payload?.notes ?? ""
            location = payload?.location ?? ""
            startDate = nil
            endDate = nil
            dueDate = CandidateDraft.parseReminderDate(payload)
            dueTime = payload?.dueTime
            hasDueDate = dueDate != nil
            recurrence = payload?.recurrence.map(RecurrenceRule.from)
            alertMinutesBeforeStart = 10
            alertMinutesBeforeDue = payload?.alertMinutesBeforeDue
            calendarName = nil
            listName = payload?.listName ?? "提醒事项"
            priority = payload?.priority ?? "none"
            flagged = payload?.flagged ?? false
            url = payload?.url.flatMap(URL.init(string:))
        }
        appliedPreferences = candidate.appliedPreferences ?? []
        missingFields = candidate.missingFields ?? []
        clarificationQuestion = candidate.clarificationQuestion ?? ""
        conflicts = candidate.conflicts ?? []
        status = candidate.status ?? (missingFields.isEmpty ? "ready" : "needs_input")
        if id.isEmpty {
            status = "error"
            error = "候选项缺少 ID: \(fallbackIndex)"
        }
        originalFingerprint = fingerprint
    }

    var summary: String {
        if kind == "calendar", missingFields.contains("time") {
            return "缺少开始时间"
        }
        if kind == "calendar", let startDate {
            if let endDate {
                return "\(Self.shortDateTimeFormatter.string(from: startDate)) - \(Self.timeFormatter.string(from: endDate))"
            }
            return Self.shortDateTimeFormatter.string(from: startDate)
        }
        if let dueDate {
            return "提醒 " + Self.shortDateTimeFormatter.string(from: dueDate)
        }
        return kind == "calendar" ? "缺少时间" : "无截止时间"
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == "calendar" ? "未命名日程" : "未命名待办"
    }

    var kindLabel: String {
        kind == "calendar" ? "日程" : "待办"
    }

    var tintColor: Color {
        kind == "calendar" ? .blue : .green
    }

    var primaryDateLabel: String {
        if kind == "calendar", let startDate {
            return Self.dateHeadlineFormatter.string(from: startDate)
        }
        if let dueDate {
            return Self.dateHeadlineFormatter.string(from: dueDate)
        }
        return "待补充时间"
    }

    var primaryDateIsMissing: Bool {
        if kind == "calendar" {
            return startDate == nil
        }
        return dueDate == nil && missingFields.contains("time")
    }

    var primaryTimeLabel: String {
        if kind == "calendar" {
            guard let startDate else { return "待补充" }
            return Self.timeFormatter.string(from: startDate)
        }
        guard hasDueDate, let dueDate else { return "未设置" }
        if dueTime == nil && missingFields.contains("time") {
            return "待补充"
        }
        return Self.timeFormatter.string(from: dueDate)
    }

    var endTimeLabel: String {
        guard kind == "calendar" else { return "" }
        guard let endDate else { return "待补充" }
        return Self.timeFormatter.string(from: endDate)
    }

    var primaryTimeIsMissing: Bool {
        if kind == "calendar" {
            return startDate == nil || missingFields.contains("time")
        }
        return missingFields.contains("time") || (hasDueDate && dueTime == nil)
    }

    var endTimeIsMissing: Bool {
        kind == "calendar" && (endDate == nil || missingFields.contains("duration"))
    }

    var locationLabel: String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var statusLabel: String {
        switch status {
        case "written": return "已写入"
        case "skipped": return "已跳过"
        case "conflict": return "冲突"
        case "needs_input": return "待补充"
        case "checking_conflict": return "检查冲突"
        case "updating": return "更新中"
        case "writing": return "写入中"
        case "replacing": return "替换中"
        case "error": return "错误"
        default: return "待写入"
        }
    }

    var statusColor: Color {
        switch status {
        case "written": return .green
        case "skipped": return .secondary
        case "conflict": return .orange
        case "needs_input", "updating", "checking_conflict", "writing", "replacing": return .blue
        case "error": return .red
        default: return .primary
        }
    }

    var needsInput: Bool {
        !missingFields.isEmpty || status == "needs_input"
    }

    var hasAppliedPreferences: Bool {
        !appliedPreferences.isEmpty
    }

    var showsConversationBox: Bool {
        needsInput || hasAppliedPreferences
    }

    var isPassive: Bool {
        ["written", "skipped", "error"].contains(status)
    }

    var canWrite: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard missingFields.isEmpty else { return false }
        if kind == "calendar" {
            guard let startDate, let endDate else { return false }
            return endDate > startDate
        }
        return true
    }

    var isModified: Bool {
        fingerprint != originalFingerprint
    }

    var missingPrompt: String {
        if missingFields.contains("time") {
            return kind == "calendar" ? "几点开始？" : "什么时候提醒？"
        }
        if missingFields.contains("duration") {
            return "持续多久？"
        }
        if missingFields.contains("location") {
            return "在哪里？"
        }
        if missingFields.contains("title") {
            return "标题是什么？"
        }
        return "请补充这项信息"
    }

    var clarificationPrompt: String {
        let trimmed = clarificationQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? missingPrompt : trimmed
    }

    var conversationPrompt: String {
        if needsInput {
            return clarificationPrompt
        }
        if let message = appliedPreferences.first?.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "可以直接写入，也可以继续补充修改。"
    }

    func preferenceMarked(_ value: String, fields: [String]) -> String {
        let applied = Set(appliedPreferences.map(\.field))
        return fields.contains { applied.contains($0) } ? "\(value) · 按偏好" : value
    }

    var calendarTimeSummary: String {
        guard kind == "calendar" else { return "" }
        guard let startDate else { return "待确认时间" }
        if missingFields.contains("time") {
            return endTimeIsMissing
                ? "\(Self.dateHeadlineFormatter.string(from: startDate)) · 待确认开始时间和时长"
                : "\(Self.dateHeadlineFormatter.string(from: startDate)) · 待确认开始时间"
        }
        let startText = "\(Self.dateHeadlineFormatter.string(from: startDate)) \(Self.timeFormatter.string(from: startDate))"
        guard let endDate else {
            return "\(startText) - 待确认结束时间"
        }
        let endText: String
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            endText = Self.timeFormatter.string(from: endDate)
        } else {
            endText = Self.shortDateTimeFormatter.string(from: endDate)
        }
        return "\(startText) - \(endText)"
    }

    var reminderDueSummary: String {
        guard kind != "calendar" else { return "" }
        guard hasDueDate, let dueDate else {
            return missingFields.contains("time") ? "待确认提醒时间" : "无截止时间"
        }
        if dueTime == nil && missingFields.contains("time") {
            return "\(Self.dateHeadlineFormatter.string(from: dueDate)) · 待确认提醒时间"
        }
        let base = dueTime == nil
            ? Self.dateHeadlineFormatter.string(from: dueDate)
            : "\(Self.dateHeadlineFormatter.string(from: dueDate)) \(Self.timeFormatter.string(from: dueDate))"
        guard let alertMinutesBeforeDue else { return base }
        return "\(base) · \(Self.alertLabel(minutes: alertMinutesBeforeDue))"
    }

    var calendarAlertLabel: String {
        Self.alertLabel(minutes: alertMinutesBeforeStart)
    }

    var reminderFlagLabel: String {
        var parts: [String] = []
        if flagged { parts.append("已标记") }
        if priority != "none" { parts.append(Self.priorityLabel(priority)) }
        return parts.isEmpty ? "无" : parts.joined(separator: " · ")
    }

    var recurrenceSummary: String? {
        guard let recurrence else { return nil }
        var text: String
        switch recurrence.frequency {
        case "daily": text = "每天"
        case "weekly": text = "每周"
        case "monthly": text = "每月"
        case "yearly": text = "每年"
        default: text = "重复"
        }
        if recurrence.interval > 1 {
            text = "每 \(recurrence.interval) " + Self.recurrenceUnit(recurrence.frequency)
        }
        if let weekdays = recurrence.weekdays, !weekdays.isEmpty {
            text += " " + weekdays.map(Self.weekdayLabel).joined(separator: "、")
        }
        if let occurrenceCount = recurrence.occurrenceCount, occurrenceCount > 0 {
            text += "，共 \(occurrenceCount) 次"
        } else if let endDate = recurrence.endDate {
            text += "，至 \(Self.dateHeadlineFormatter.string(from: endDate))"
        }
        return text
    }

    var notesSummary: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var urlSummary: String? {
        guard let url else { return nil }
        return url.host ?? url.absoluteString
    }

    var corrections: [String: String] {
        var values: [String: String] = [
            "id": id,
            "kind": kind,
            "title": title,
            "notes": notes,
            "location": location,
            "status": status,
            "missing_fields": missingFields.joined(separator: ","),
        ]
        if let startDate { values["start_time"] = iso(startDate) }
        if let endDate { values["end_time"] = iso(endDate) }
        if let dueDate { values["due_date"] = iso(dueDate) }
        if let dueTime { values["due_time"] = dueTime }
        values["list_name"] = listName
        values["priority"] = priority
        return values
    }

    var calendarRecognition: CalendarRecognition {
        CalendarRecognition(
            title: title.isEmpty ? "新日程" : title,
            notes: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            startTime: startDate,
            endTime: endDate,
            isAllDay: false,
            needsDuration: false,
            recurrence: recurrence,
            travelTimeMinutes: nil,
            alertMinutesBeforeStart: alertMinutesBeforeStart,
            calendarName: calendarName,
            url: url
        )
    }

    var reminderRecognition: ReminderRecognition {
        ReminderRecognition(
            title: title.isEmpty ? "新提醒" : title,
            notes: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            dueDate: hasDueDate ? dueDate : nil,
            dueTime: hasDueDate ? (dueTime ?? formatTime(dueDate)) : nil,
            recurrence: recurrence,
            alertMinutesBeforeDue: alertMinutesBeforeDue,
            listName: listName,
            priority: priority,
            flagged: flagged,
            url: url
        )
    }

    var finalCandidateSnapshot: RecognitionCandidate {
        RecognitionCandidate(
            id: id,
            kind: kind,
            calendar: kind == "calendar" ? calendarPayloadSnapshot : nil,
            reminder: kind == "reminder" ? reminderPayloadSnapshot : nil,
            confidence: nil,
            evidence: nil,
            missingFields: missingFields,
            clarificationQuestion: clarificationQuestion.isEmpty ? nil : clarificationQuestion,
            conflicts: conflicts,
            status: status,
            appliedPreferences: appliedPreferences
        )
    }

    private var calendarPayloadSnapshot: CalendarPayload {
        CalendarPayload(
            title: title.isEmpty ? nil : title,
            notes: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            startTime: optionalIso(startDate),
            endTime: optionalIso(endDate),
            isAllDay: false,
            needsDuration: endDate == nil,
            recurrence: recurrence?.payload,
            travelTimeMinutes: nil,
            alertMinutesBeforeStart: alertMinutesBeforeStart,
            calendarName: calendarName,
            url: url?.absoluteString
        )
    }

    private var reminderPayloadSnapshot: ReminderPayload {
        ReminderPayload(
            title: title.isEmpty ? nil : title,
            notes: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            dueDate: hasDueDate ? optionalIsoDate(dueDate) : nil,
            dueTime: hasDueDate ? (dueTime ?? formatTime(dueDate)) : nil,
            recurrence: recurrence?.payload,
            alertMinutesBeforeDue: alertMinutesBeforeDue,
            listName: listName,
            priority: priority,
            flagged: flagged,
            url: url?.absoluteString
        )
    }

    mutating func applyFollowup(_ candidate: RecognitionCandidate) {
        guard candidate.kind == kind else {
            status = "error"
            error = "更新结果类型不匹配"
            return
        }

        let incomingMissing = candidate.missingFields ?? []
        if kind == "calendar", let payload = candidate.calendar {
            title = payload.title ?? title
            notes = payload.notes ?? notes
            location = payload.location ?? location
            startDate = RecognitionResult.parseDate(payload.startTime) ?? startDate
            if let parsedEnd = RecognitionResult.parseDate(payload.endTime) {
                endDate = parsedEnd
            } else if payload.needsDuration == true || incomingMissing.contains("duration") {
                endDate = nil
            } else if let startDate {
                endDate = startDate.addingTimeInterval(3600)
            }
            recurrence = payload.recurrence.map(RecurrenceRule.from) ?? recurrence
            alertMinutesBeforeStart = payload.alertMinutesBeforeStart ?? alertMinutesBeforeStart
            calendarName = payload.calendarName ?? calendarName
            url = payload.url.flatMap { URL(string: $0) } ?? url
        } else if let payload = candidate.reminder {
            title = payload.title ?? title
            notes = payload.notes ?? notes
            location = payload.location ?? location
            dueDate = CandidateDraft.parseReminderDate(payload) ?? dueDate
            dueTime = payload.dueTime ?? dueTime
            hasDueDate = dueDate != nil
            recurrence = payload.recurrence.map(RecurrenceRule.from) ?? recurrence
            alertMinutesBeforeDue = payload.alertMinutesBeforeDue ?? alertMinutesBeforeDue
            listName = payload.listName ?? listName
            priority = payload.priority ?? priority
            flagged = payload.flagged ?? flagged
            url = payload.url.flatMap { URL(string: $0) } ?? url
        }

        missingFields = incomingMissing
        appliedPreferences = candidate.appliedPreferences ?? []
        clarificationQuestion = candidate.clarificationQuestion ?? ""
        conflicts = []
        selectedConflictIDs = []
        allowConflictWrite = false
        error = nil
        status = candidate.status ?? (missingFields.isEmpty ? "ready" : "needs_input")
        refreshInputStatus()
    }

    mutating func resolveMissing(_ field: String) {
        missingFields.removeAll { $0 == field }
        clarificationQuestion = ""
        refreshInputStatus()
    }

    mutating func refreshInputStatus() {
        if !missingFields.isEmpty {
            status = "needs_input"
        } else if !conflicts.isEmpty && !allowConflictWrite {
            status = "conflict"
        } else if status == "needs_input" || status == "conflict" || status == "ready" {
            status = "ready"
            clarificationQuestion = ""
        }
    }

    func formatTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func missingLabel(_ field: String) -> String {
        switch field {
        case "title": return "标题"
        case "time": return "时间"
        case "duration": return "时长"
        case "location": return "地点"
        default: return field
        }
    }

    private static func parseReminderDate(_ payload: ReminderPayload?) -> Date? {
        guard let payload else { return nil }
        if let dueDate = payload.dueDate, let dueTime = payload.dueTime, !dueDate.contains("T") {
            let normalizedTime = dueTime.count == 5 ? "\(dueTime):00" : dueTime
            return RecognitionResult.parseDate("\(dueDate)T\(normalizedTime)")
        }
        return RecognitionResult.parseDate(payload.dueDate)
    }

    private var fingerprint: String {
        [
            kind,
            title,
            notes,
            location,
            iso(startDate),
            iso(endDate),
            iso(dueDate),
            dueTime ?? "",
            hasDueDate ? "1" : "0",
            calendarName ?? "",
            listName,
            priority,
            flagged ? "1" : "0",
            url?.absoluteString ?? "",
        ].joined(separator: "|")
    }

    private func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func optionalIso(_ date: Date?) -> String? {
        let value = iso(date)
        return value.isEmpty ? nil : value
    }

    private func isoDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func optionalIsoDate(_ date: Date?) -> String? {
        let value = isoDate(date)
        return value.isEmpty ? nil : value
    }

    private static let dateHeadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func alertLabel(minutes: Int) -> String {
        if minutes <= 0 { return "准时提醒" }
        if minutes % 1440 == 0 { return "提前 \(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "提前 \(minutes / 60) 小时" }
        return "提前 \(minutes) 分钟"
    }

    private static func priorityLabel(_ priority: String) -> String {
        switch priority {
        case "high": return "高优先级"
        case "medium": return "中优先级"
        case "low": return "低优先级"
        default: return "无优先级"
        }
    }

    private static func recurrenceUnit(_ frequency: String) -> String {
        switch frequency {
        case "daily": return "天"
        case "weekly": return "周"
        case "monthly": return "个月"
        case "yearly": return "年"
        default: return "周期"
        }
    }

    private static func weekdayLabel(_ weekday: String) -> String {
        switch weekday {
        case "monday": return "周一"
        case "tuesday": return "周二"
        case "wednesday": return "周三"
        case "thursday": return "周四"
        case "friday": return "周五"
        case "saturday": return "周六"
        case "sunday": return "周日"
        default: return weekday
        }
    }
}

private extension RecurrenceRule {
    var payload: RecurrencePayload {
        RecurrencePayload(
            frequency: frequency,
            interval: interval,
            weekdays: weekdays,
            endDate: formattedEndDate,
            occurrenceCount: occurrenceCount
        )
    }

    var formattedEndDate: String? {
        guard let endDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: endDate)
    }
}

private extension Array where Element == String {
    mutating func appendIfMissing(_ value: String) {
        if !contains(value) {
            append(value)
        }
    }
}

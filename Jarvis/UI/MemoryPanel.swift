import AppKit
import SwiftUI

struct MemoryPanel: View {
    @State private var files: [MemoryFile] = []
    @State private var drafts: [String: String] = [:]
    @State private var selectedId = "soul"
    @State private var editModeIds: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var statusText: String?

    private let fileOrder = ["soul", "user", "heartbeat"]

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)

            editorPane
                .frame(minWidth: 560)
        }
        .frame(minWidth: 760, minHeight: 500)
        .task {
            await loadFiles(replaceDrafts: true)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Memory", systemImage: "brain")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            List {
                ForEach(orderedFiles, id: \.id) { file in
                    Button {
                        Task { await select(file) }
                    } label: {
                        memoryRow(file)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                toolbar(for: file)
                Divider()
                editor(for: file)
                Divider()
                footer(for: file)
            } else {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                    }
                    Text(isLoading ? "加载中" : "未找到 Memory 文件")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var orderedFiles: [MemoryFile] {
        files.sorted { lhs, rhs in
            let left = fileOrder.firstIndex(of: lhs.id) ?? Int.max
            let right = fileOrder.firstIndex(of: rhs.id) ?? Int.max
            return left == right ? lhs.filename < rhs.filename : left < right
        }
    }

    private var selectedFile: MemoryFile? {
        files.first { $0.id == selectedId } ?? files.first
    }

    private func memoryRow(_ file: MemoryFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.editable ? "doc.text" : "lock.doc")
                .font(.system(size: 14))
                .foregroundStyle(file.editable ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.title)
                    .font(.system(size: 13, weight: selectedId == file.id ? .semibold : .regular))
                    .lineLimit(1)
                Text(file.editable ? "可编辑" : "只读")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDirty(file) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedId == file.id ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }

    private func toolbar(for file: MemoryFile) -> some View {
        HStack(spacing: 10) {
            Text(file.title)
                .font(.system(size: 16, weight: .semibold))

            Label(file.editable ? "可编辑" : "只读", systemImage: file.editable ? "square.and.pencil" : "lock")
                .font(.system(size: 12))
                .foregroundStyle(file.editable ? Color.accentColor : Color.secondary)

            if isDirty(file) {
                Label("未保存", systemImage: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if file.editable {
                Button {
                    toggleEditMode(for: file)
                } label: {
                    Label(isEditing(file) ? "预览" : "编辑", systemImage: isEditing(file) ? "doc.richtext" : "pencil")
                }
                .disabled(isLoading || isSaving)
            }

            Button {
                Task { await reloadSelected() }
            } label: {
                Label("重载", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || isSaving)

            Button {
                Task { _ = await saveSelected() }
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .disabled(!file.editable || !isDirty(file) || isLoading || isSaving)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func editor(for file: MemoryFile) -> some View {
        if file.editable && isEditing(file) {
            TextEditor(
                text: Binding(
                    get: { draftText(for: file) },
                    set: { newValue in
                        drafts[file.id] = newValue
                        statusText = nil
                    }
                )
            )
            .font(.system(size: 13, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(isLoading || isSaving)
        } else if file.editable {
            markdownPreview(for: file)
        } else {
            ScrollView([.vertical, .horizontal]) {
                Text(draftText(for: file).isEmpty ? " " : draftText(for: file))
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func markdownPreview(for file: MemoryFile) -> some View {
        ScrollView {
            MarkdownPreview(markdown: draftText(for: file).isEmpty ? " " : draftText(for: file))
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(for file: MemoryFile) -> some View {
        HStack(spacing: 10) {
            if file.truncated == true {
                Label("仅展示最近日志", systemImage: "scissors")
                    .foregroundStyle(.orange)
            }

            Text("\(file.byteSize ?? draftText(for: file).utf8.count) bytes")
                .foregroundStyle(.secondary)

            Spacer()

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let statusText {
                Label(statusText, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func loadFiles(replaceDrafts: Bool) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response = try await GatewayClient.shared.memoryFiles()
            let loaded = response.files ?? []
            files = loaded
            if !loaded.contains(where: { $0.id == selectedId }) {
                selectedId = orderedFiles.first?.id ?? "soul"
            }
            for file in loaded where replaceDrafts || drafts[file.id] == nil {
                drafts[file.id] = file.content ?? ""
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func select(_ file: MemoryFile) async {
        guard file.id != selectedId else { return }
        if let current = selectedFile, isDirty(current) {
            switch askUnsavedChoice(filename: current.filename) {
            case .save:
                guard await saveSelected() else { return }
            case .discard:
                drafts[current.id] = current.content ?? ""
            case .cancel:
                return
            }
        }
        selectedId = file.id
        errorText = nil
        statusText = nil
    }

    private func saveSelected() async -> Bool {
        guard let file = selectedFile, file.editable else { return false }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let response = try await GatewayClient.shared.updateMemoryFile(
                fileId: file.id,
                content: draftText(for: file)
            )
            replace(response.file)
            drafts[file.id] = response.file.content ?? ""
            editModeIds.remove(file.id)
            statusText = "已保存 \(response.file.filename)"
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    private func reloadSelected() async {
        guard let file = selectedFile else { return }
        if isDirty(file) && !confirmDiscardReload(filename: file.filename) {
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response = try await GatewayClient.shared.memoryFiles()
            guard let updated = (response.files ?? []).first(where: { $0.id == file.id }) else { return }
            replace(updated)
            drafts[file.id] = updated.content ?? ""
            editModeIds.remove(file.id)
            statusText = "已重载 \(updated.filename)"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func replace(_ file: MemoryFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            files[index] = file
        } else {
            files.append(file)
        }
    }

    private func draftText(for file: MemoryFile) -> String {
        drafts[file.id] ?? file.content ?? ""
    }

    private func isDirty(_ file: MemoryFile) -> Bool {
        guard let draft = drafts[file.id] else { return false }
        return draft != (file.content ?? "")
    }

    private func isEditing(_ file: MemoryFile) -> Bool {
        file.editable && editModeIds.contains(file.id)
    }

    private func toggleEditMode(for file: MemoryFile) {
        if isEditing(file) {
            editModeIds.remove(file.id)
        } else {
            editModeIds.insert(file.id)
        }
    }

    private func askUnsavedChoice(filename: String) -> UnsavedChoice {
        let alert = NSAlert()
        alert.messageText = "保存对 \(filename) 的修改？"
        alert.informativeText = "切换前可以保存或丢弃未保存内容。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "丢弃")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func confirmDiscardReload(filename: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "放弃未保存修改并重载 \(filename)？"
        alert.informativeText = "重载会从 Jarvis memory 文件重新读取内容。"
        alert.addButton(withTitle: "重载")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private enum UnsavedChoice {
        case save
        case discard
        case cancel
    }
}

private struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .blank:
                    Spacer()
                        .frame(height: 4)
                case .heading(let level, let text):
                    markdownText(text)
                        .font(font(forHeadingLevel: level))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 2 : 8)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        markdownText(text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .paragraph(let text):
                    markdownText(text)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MarkdownBlock] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return .blank
            }

            if let heading = parseHeading(trimmed) {
                return heading
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return .bullet(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }

            return .paragraph(line)
        }
    }

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private func markdownText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(markdown: markdown) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 22, weight: .semibold)
        case 2:
            return .system(size: 17, weight: .semibold)
        case 3:
            return .system(size: 15, weight: .semibold)
        default:
            return .system(size: 13, weight: .semibold)
        }
    }

    private enum MarkdownBlock {
        case blank
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }
}

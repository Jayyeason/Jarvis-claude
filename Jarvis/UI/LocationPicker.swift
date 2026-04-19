import SwiftUI

struct LocationPicker: View {
    let keyword: String
    let onSelect: (LocationResult) -> Void
    let onCancel: () -> Void

    @State private var results: [LocationResult] = []
    @State private var selectedId: UUID?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择地点")
                        .font(.system(size: 15, weight: .semibold))
                    Text("已搜索：\(keyword)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            if isLoading {
                ProgressView("搜索中...")
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else if results.isEmpty {
                Text("未找到相关地点")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { loc in
                            LocationRow(
                                result: loc,
                                isSelected: selectedId == loc.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedId = loc.id }

                            if loc.id != results.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            HStack {
                Button("手动输入地址...") {
                    // Use keyword as-is (no coordinates)
                    let manual = LocationResult(
                        name: keyword, address: "", latitude: 0, longitude: 0, distance: nil
                    )
                    onSelect(manual)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

                Spacer()

                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)

                Button("确认") {
                    if let id = selectedId, let loc = results.first(where: { $0.id == id }) {
                        onSelect(loc)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedId == nil)
            }
            .padding(16)
        }
        .frame(width: 300)
        .task { await loadResults() }
    }

    private func loadResults() async {
        results = await MapKitTool.search(keyword: keyword)
        selectedId = results.first?.id
        isLoading = false
    }
}

private struct LocationRow: View {
    let result: LocationResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                if !result.address.isEmpty {
                    Text(result.address)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !result.distanceText.isEmpty {
                Text(result.distanceText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

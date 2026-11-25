import SwiftUI

/// Drag to reorder, in sections (accounts by type, categories by kind). Same screen on Android (ReorderSheet).
struct ReorderItem: Identifiable, Hashable {
  let id: String
  let name: String
  let icon: String
  let color: String
}

struct ReorderGroup {
  let title: String
  var items: [ReorderItem]
}

struct ReorderView: View {
  let title: String
  @State var groups: [ReorderGroup]
  /// Each group's ids in the new order; the caller writes sortOrder = index.
  let onSave: ([[String]]) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      ForEach(groups.indices, id: \.self) { g in
        Section(groups.count > 1 ? groups[g].title : "") {
          ForEach(groups[g].items) { item in
            HStack(spacing: 12) {
              CategoryBadge(icon: item.icon, color: item.color, size: 30)
              Text(item.name)
            }
          }
          .onMove { from, to in groups[g].items.move(fromOffsets: from, toOffset: to); Haptic.soft() }
        }
      }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { onSave(groups.map { $0.items.map(\.id) }); dismiss() }.fontWeight(.semibold)
      }
    }
  }
}

import StillCore
import SwiftUI

struct ShelfView: View {
  @ObservedObject var store: AppStore
  @FocusState private var capturing: Bool
  @State private var showResolved = false
  @State private var expandedNotes: Set<UUID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Notes").font(.system(size: 14, weight: .semibold))
        Spacer()
        Menu {
          Toggle("Show resolved notes", isOn: $showResolved)
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(
          "Notes options")
      }.padding(.bottom, 18)
      HStack(alignment: .top, spacing: 6) {
        TextField("Write a note…", text: $store.thoughtDraft, axis: .vertical)
          .lineLimit(2...5).font(.system(size: 12)).textFieldStyle(.plain)
          .focused($capturing).onSubmit(store.captureThought).accessibilityLabel("New note")
        Button(action: store.captureThought) {
          Image(systemName: "arrow.turn.down.left").font(.system(size: 10))
        }
        .buttonStyle(IconButton()).disabled(
          store.thoughtDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .accessibilityLabel("Save note")
      }.padding(10).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6).stroke(
            capturing ? Palette.muted : Palette.line, lineWidth: 1))
      Text("Return to save · ⇧ Return for a new line").font(.system(size: 9)).foregroundStyle(
        Palette.muted
      ).padding(.top, 8).padding(.bottom, 20)
      if notes.isEmpty {
        Text("Capture a thought without leaving your session.")
          .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top, 8)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(notes) { note in
            VStack(alignment: .leading, spacing: 10) {
              Text(note.text).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                .foregroundStyle(note.isDone ? Palette.muted : Palette.ink)
                .strikethrough(note.isDone).lineLimit(expandedNotes.contains(note.id) ? nil : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
              if note.text.count > 250 || note.text.components(separatedBy: "\n").count > 6 {
                Button(expandedNotes.contains(note.id) ? "Show less" : "Show more") {
                  if expandedNotes.contains(note.id) {
                    expandedNotes.remove(note.id)
                  } else {
                    expandedNotes.insert(note.id)
                  }
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
              }
              HStack {
                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                  .font(.system(size: 9)).foregroundStyle(Palette.muted)
                Spacer()
                Button {
                  store.toggleThought(note.id)
                } label: {
                  Image(systemName: note.isDone ? "arrow.uturn.backward" : "checkmark").font(
                    .system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted).help(
                  note.isDone ? "Reopen note" : "Resolve note"
                )
                .accessibilityLabel(note.isDone ? "Reopen note" : "Resolve note")
              }
            }.padding(.vertical, 15).overlay(alignment: .bottom) {
              Rectangle().fill(Palette.line).frame(height: 1)
            }
          }
        }
      }
      Spacer(minLength: 0)
    }.padding(22).background(Palette.panel.opacity(0.45))
      .onReceive(NotificationCenter.default.publisher(for: .captureThought)) { _ in capturing = true
      }
      .onAppear { capturing = true }
  }
  private var notes: [Thought] { store.state.thoughts.filter { showResolved || !$0.isDone } }
}

extension Notification.Name {
  static let captureThought = Notification.Name("Still.captureThought")
  static let newTask = Notification.Name("Still.newTask")
}

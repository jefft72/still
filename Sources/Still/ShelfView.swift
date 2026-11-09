import StillCore
import SwiftUI

struct ShelfView: View {
  @ObservedObject var store: AppStore
  @State private var focusRequest = 0
  @State private var showResolved = false

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
        .tint(Palette.muted).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(
          "Notes options")
      }.padding(.bottom, 18)
      HStack(alignment: .top, spacing: 6) {
        ZStack(alignment: .topLeading) {
          NoteEditor(
            text: $store.thoughtDraft, focusRequest: focusRequest, onSubmit: store.captureThought
          )
          .frame(height: 60)
          if store.thoughtDraft.isEmpty {
            Text("Write a note…").font(.system(size: 12)).foregroundStyle(
              Palette.muted.opacity(0.7)
            )
            .allowsHitTesting(false)
          }
        }
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
            Palette.line, lineWidth: 1))
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
                .strikethrough(note.isDone)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityElement(children: .ignore)
                .accessibilityRemoveTraits(.isSelected)
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
      .onReceive(NotificationCenter.default.publisher(for: .captureThought)) { _ in
        focusRequest += 1
      }
      .onAppear { focusRequest += 1 }
  }
  private var notes: [Thought] { store.state.thoughts.filter { showResolved || !$0.isDone } }
}

extension Notification.Name {
  static let captureThought = Notification.Name("Still.captureThought")
  static let newTask = Notification.Name("Still.newTask")
}

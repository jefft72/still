import SwiftUI

struct ProjectEditor: View {
  @ObservedObject var store: AppStore
  @Binding var name: String
  let projectID: UUID?
  let onSave: () -> Void
  @Environment(\.dismiss) private var dismiss
  @FocusState private var nameFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 7) {
        Text(projectID == nil ? "New project" : "Rename project")
          .font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader)
      }
      VStack(alignment: .leading, spacing: 9) {
        Text("Project name").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
        TextField("e.g. Website redesign", text: $name)
          .textFieldStyle(.plain).font(.system(size: 13))
          .padding(.horizontal, 11).frame(height: 36)
          .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(
              nameUnavailable ? Palette.accent : Palette.line, lineWidth: 1)
          )
          .focused($nameFocused).onSubmit(save)
          .accessibilityLabel("Project name")
          .accessibilityHint(nameUnavailable ? "A project with this name already exists." : "")
        Text(
          nameUnavailable
            ? "A project with this name already exists."
            : " "
        )
        .font(.system(size: 11)).foregroundStyle(nameUnavailable ? Palette.accent : Palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 8) {
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
        Button(projectID == nil ? "Create project" : "Save changes", action: save)
          .buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(!canSave)
      }
    }
    .padding(26).frame(width: 420).background(Palette.background).foregroundStyle(Palette.ink)
    .tint(Palette.accent).preferredColorScheme(.light)
    .defaultFocus($nameFocused, true)
    .onAppear { nameFocused = true }
  }

  private var nameUnavailable: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return store.state.projects.contains {
      $0.id != projectID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !nameUnavailable
  }

  private func save() {
    guard canSave else { return }
    onSave()
    dismiss()
  }
}

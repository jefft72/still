import AppKit
import StillCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportTasksView: View {
  @ObservedObject var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var projectID: UUID?
  @State private var queued = true
  @State private var error: String?
  @State private var parsed: [ImportedTask] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Import tasks").font(.system(size: 18, weight: .semibold))
        Spacer()
        Button("Choose file…", action: chooseFile).buttonStyle(QuietButton())
      }
      Text(
        "Paste a list or Markdown checklist. Each item becomes a task; checked items stay completed."
      )
      .font(.system(size: 12)).lineSpacing(4).foregroundStyle(Palette.muted)
      TextEditor(text: $text).font(.system(size: 12, design: .monospaced))
        .scrollContentBackground(.hidden).padding(10).frame(height: 220)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
        .accessibilityLabel("Task list to import").onChange(of: text) { _, _ in parse() }
      HStack(spacing: 16) {
        Picker("Project", selection: $projectID) {
          Text("No project").tag(nil as UUID?)
          ForEach(store.state.projects) { project in Text(project.name).tag(Optional(project.id)) }
        }.frame(maxWidth: 260)
        Spacer()
        Toggle("Add to Today", isOn: $queued).toggleStyle(.checkbox).font(.system(size: 12))
      }
      if let error {
        Text(error).font(.system(size: 12)).foregroundStyle(Palette.accent)
      } else {
        Text(
          "\(parsed.count) \(parsed.count == 1 ? "task" : "tasks") · \(parsed.filter(\.isComplete).count) completed"
        )
        .font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      HStack {
        Text("Your existing tasks won't change.").font(.system(size: 11)).foregroundStyle(
          Palette.muted)
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
        Button("Import \(parsed.count) tasks") {
          store.importTasks(parsed, projectID: projectID, queued: queued)
          dismiss()
        }.buttonStyle(PrimaryButton()).disabled(parsed.isEmpty || error != nil)
          .keyboardShortcut(.return, modifiers: .command)
      }
    }.padding(26).frame(width: 560).background(Palette.background).foregroundStyle(Palette.ink)
      .tint(Palette.accent).preferredColorScheme(.light)
  }
  private func parse() {
    do {
      parsed = try TaskImport.parse(text)
      error = nil
    } catch {
      parsed = []
      self.error = error.localizedDescription
    }
  }
  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.title = "Import a task list"
    panel.prompt = "Choose"
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.plainText, .text]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 800_000 else { throw TaskImport.ImportError.tooLarge }
      text = try String(contentsOf: url, encoding: .utf8)
      parse()
    } catch { self.error = error.localizedDescription }
  }
}

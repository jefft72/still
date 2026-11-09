import AppKit
import StillCore
import SwiftUI

struct TaskEditor: View {
  @ObservedObject var store: AppStore
  @State var task: TaskItem
  @Environment(\.dismiss) private var dismiss
  @State private var linkURL = ""
  @State private var linkError: String?
  @FocusState private var titleFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Task details").font(.system(size: 13, weight: .semibold))
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
        Button("Save changes") {
          store.updateTask(task)
          dismiss()
        }
        .buttonStyle(PrimaryButton()).keyboardShortcut(.return, modifiers: .command)
        .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.padding(22)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          TextField("Task title", text: $task.title, axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: 23, weight: .semibold)).lineLimit(1...4)
            .focused($titleFocused).accessibilityLabel("Task title")
          HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
              fieldLabel("Project")
              Picker("Project", selection: $task.projectID) {
                Text("No project").tag(nil as UUID?)
                ForEach(store.state.projects) { project in
                  Text(project.name).tag(Optional(project.id))
                }
              }.labelsHidden().frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
              fieldLabel("Session length")
              HStack(spacing: 7) {
                TextField("Minutes", value: $task.estimateMinutes, format: .number)
                  .textFieldStyle(.roundedBorder).frame(width: 55).accessibilityLabel(
                    "Task session minutes")
                Text("min").font(.system(size: 12)).foregroundStyle(Palette.muted)
              }
            }
          }
          Toggle("Include in Today", isOn: $task.isQueued).toggleStyle(.checkbox).font(
            .system(size: 12))
          VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Notes")
            TextEditor(text: $task.notes).font(.system(size: 13)).lineSpacing(4)
              .scrollContentBackground(.hidden).padding(8).frame(minHeight: 130)
              .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
              .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
              .accessibilityLabel("Task notes")
          }
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              fieldLabel("References")
              Spacer()
              Button {
                attachFile()
              } label: {
                Label("Attach file", systemImage: "paperclip").font(.system(size: 11))
              }
              .buttonStyle(QuietButton())
            }
            ForEach(task.links) { link in
              HStack(spacing: 10) {
                Image(systemName: link.url.hasPrefix("file:") ? "doc" : "link").font(
                  .system(size: 12)
                ).foregroundStyle(Palette.muted)
                Button {
                  open(link)
                } label: {
                  Text(link.title.isEmpty ? link.url : link.title).font(.system(size: 12))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(Palette.ink)
                Button {
                  task.links.removeAll { $0.id == link.id }
                } label: {
                  Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(IconButton()).help("Remove reference").accessibilityLabel(
                  "Remove \(link.title)")
              }.padding(.horizontal, 10).frame(height: 34).background(
                Palette.panel, in: RoundedRectangle(cornerRadius: 5))
            }
            HStack(spacing: 8) {
              TextField("Paste a URL…", text: $linkURL).textFieldStyle(.roundedBorder).font(
                .system(size: 12)
              )
              .onSubmit(addLink).accessibilityLabel("Reference URL")
              Button("Add", action: addLink).buttonStyle(QuietButton()).disabled(linkURL.isEmpty)
            }
            if let error = linkError {
              Text(error).font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
          }
          HStack {
            Button("Copy task brief") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                WorkExport.brief(
                  task: task, project: store.state.projects.first { $0.id == task.projectID }),
                forType: .string)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .omitted))").font(
              .system(size: 10)
            ).foregroundStyle(Palette.muted)
            Spacer()
            let count = store.state.history.filter { $0.taskID == task.id }.count
            Text("\(count) completed \(count == 1 ? "session" : "sessions")").font(
              .system(size: 10)
            ).foregroundStyle(Palette.muted)
          }
        }.padding(26)
      }
    }.frame(width: 500, height: 620).background(Palette.background).foregroundStyle(Palette.ink)
      .tint(Palette.accent).preferredColorScheme(.light)
  }

  private func fieldLabel(_ title: String) -> some View {
    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
  }
  private func addLink() {
    let raw = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = raw.contains("://") ? raw : "https://" + raw
    guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
      let host = url.host, !host.isEmpty
    else {
      linkError = "Enter a valid http or https URL."
      return
    }
    task.links.append(TaskLink(title: url.host ?? raw, url: url.absoluteString))
    linkURL = ""
    linkError = nil
  }
  private func attachFile() {
    let panel = NSOpenPanel()
    panel.title = "Attach a reference"
    panel.prompt = "Attach"
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      task.links.append(TaskLink(title: url.lastPathComponent, url: url.absoluteString))
    }
  }
  private func open(_ link: TaskLink) {
    guard let url = URL(string: link.url),
      ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "")
    else {
      linkError = "This reference uses an unsupported URL type."
      return
    }
    if !NSWorkspace.shared.open(url) {
      linkError = "Couldn't open this reference. It may have moved."
    }
  }
}

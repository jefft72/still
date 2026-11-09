import Foundation
import StillCore
import SwiftUI

enum CommandSearchResult: Identifiable, Equatable {
  case task(TaskItem, projectName: String?)
  case project(Project)

  var id: String {
    switch self {
    case .task(let task, _): return "task-\(task.id)"
    case .project(let project): return "project-\(project.id)"
    }
  }

  var title: String {
    switch self {
    case .task(let task, _): return task.title
    case .project(let project): return project.name
    }
  }

  var subtitle: String {
    switch self {
    case .task(let task, let projectName):
      let location = projectName ?? "No project"
      return task.isComplete ? "Completed · \(location)" : "Task · \(location)"
    case .project: return "Project"
    }
  }
}

/// Stable, case-insensitive search shared by the palette and its tests.
func commandSearch(
  query: String, tasks: [TaskItem], projects: [Project], limit: Int = 12
) -> [CommandSearchResult] {
  guard limit > 0 else { return [] }
  let projectNames = Dictionary(
    projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  func taskResult(_ task: TaskItem) -> CommandSearchResult {
    .task(task, projectName: task.projectID.flatMap { projectNames[$0] })
  }
  func normalized(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
  let text = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
  if text.isEmpty {
    let active = tasks.filter { !$0.isComplete }
    let ordered = active.filter(\.isQueued) + active.filter { !$0.isQueued }
    let taskLimit = max(0, limit - min(projects.count, min(3, limit)))
    let taskResults = ordered.prefix(taskLimit).map(taskResult)
    return taskResults + projects.prefix(limit - taskResults.count).map(CommandSearchResult.project)
  }

  let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
  var matches: [(result: CommandSearchResult, rank: Int, order: Int)] = []
  func rank(_ title: String) -> Int {
    if title == text { return 0 }
    if title.hasPrefix(text) { return 1 }
    if title.contains(text) { return 2 }
    return 3
  }
  for (index, task) in tasks.enumerated() {
    let title = normalized(task.title)
    let project = task.projectID.flatMap { projectNames[$0] } ?? ""
    let searchable = normalized("\(task.title) \(task.notes) \(project)")
    guard words.allSatisfy({ searchable.contains($0) }) else { continue }
    matches.append((taskResult(task), rank(title) + (task.isComplete ? 4 : 0), index))
  }
  for (index, project) in projects.enumerated() {
    let title = normalized(project.name)
    guard words.allSatisfy({ title.contains($0) }) else { continue }
    matches.append((.project(project), rank(title), tasks.count + index))
  }
  return matches.sorted {
    $0.rank == $1.rank ? $0.order < $1.order : $0.rank < $1.rank
  }.prefix(limit).map(\.result)
}

struct CommandPalette: View {
  @ObservedObject var store: AppStore
  var onSelectTask: (TaskItem) -> Void
  var onSelectProject: (UUID) -> Void
  @Environment(\.dismiss) private var dismiss
  @FocusState private var searchFocused: Bool
  @State private var query = ""
  @State private var selectedIndex = 0

  private var results: [CommandSearchResult] {
    commandSearch(query: query, tasks: store.state.tasks, projects: store.state.projects)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        TextField("Search tasks and projects", text: $query)
          .font(.system(size: 13)).textFieldStyle(.plain)
          .foregroundStyle(Palette.ink)
          .focused($searchFocused)
          .accessibilityLabel("Search tasks and projects")
          .accessibilityIdentifier("command-search")
          .onSubmit(openSelection)
          .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
          }
          .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
          }
        Button("Esc") { dismiss() }
          .font(.system(size: 10, design: .monospaced))
          .buttonStyle(QuietButton())
          .accessibilityLabel("Close search")
      }.padding(.horizontal, 18).frame(height: 56)
      Rectangle().fill(Palette.line).frame(height: 1)
      if results.isEmpty {
        VStack(spacing: 8) {
          Text(
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "No tasks or projects yet" : "No results"
          )
          .font(.system(size: 13)).foregroundStyle(Palette.ink)
          Text(
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "Add a task or project to find it here."
              : "Try a different title, note, or project name."
          )
          .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                resultRow(result, selected: selectedIndex == index)
                  .id(result.id)
                  .onHover { inside in
                    if inside { selectedIndex = index }
                  }
              }
            }.padding(8)
          }
          .onChange(of: selectedIndex) { _, index in
            guard results.indices.contains(index) else { return }
            proxy.scrollTo(results[index].id)
          }
        }
      }
      Rectangle().fill(Palette.line).frame(height: 1)
      HStack(spacing: 16) {
        Text("↑ ↓  navigate")
        Text("Return  open")
        Spacer()
        Text("Tasks and projects")
      }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 18).frame(height: 32)
    }
    .frame(width: 520, height: 360)
    .background(Palette.background)
    .preferredColorScheme(.light)
    .onExitCommand { dismiss() }
    .onChange(of: query) { _, _ in selectedIndex = 0 }
    .onChange(of: results.map(\.id)) { _, ids in
      selectedIndex = min(selectedIndex, max(0, ids.count - 1))
    }
    .task { searchFocused = true }
  }

  private func resultRow(_ result: CommandSearchResult, selected: Bool) -> some View {
    Button {
      open(result)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(result.title).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
          Text(result.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        Spacer(minLength: 0)
        if selected {
          Text("↵").font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
      }.padding(.horizontal, 10).frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(result.title), \(result.subtitle)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func moveSelection(_ offset: Int) {
    guard !results.isEmpty else { return }
    selectedIndex = min(max(0, selectedIndex + offset), results.count - 1)
  }

  private func openSelection() {
    guard results.indices.contains(selectedIndex) else { return }
    open(results[selectedIndex])
  }

  private func open(_ result: CommandSearchResult) {
    dismiss()
    switch result {
    case .task(let task, _): onSelectTask(task)
    case .project(let project): onSelectProject(project.id)
    }
  }
}

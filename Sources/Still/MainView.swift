import AppKit
import StillCore
import SwiftUI

private enum WorkspaceSection: Hashable {
  case today, inbox, history
  case project(UUID)
}

struct MainView: View {
  @ObservedObject var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var section = WorkspaceSection.today
  @State private var newTitle = ""
  @State private var projectName = ""
  @State private var renamingProject: UUID?
  @State private var showingProjectPrompt = false
  @State private var showingNotes = false
  @State private var showingCompleted = false
  @State private var editingTask: TaskItem?
  @State private var pendingTask: TaskItem?
  @State private var removingProject: Project?
  @FocusState private var addingTask: Bool

  var body: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 198)
      Rectangle().fill(Palette.line).frame(width: 1)
      VStack(spacing: 0) {
        toolbar
        Rectangle().fill(Palette.line).frame(height: 1)
        HStack(spacing: 0) {
          workspace.frame(maxWidth: .infinity)
          if showingNotes {
            Rectangle().fill(Palette.line).frame(width: 1)
            ShelfView(store: store).frame(width: 264)
          }
        }
        bottomBar
      }
    }
    .frame(minWidth: 900, minHeight: 620)
    .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    .preferredColorScheme(.light)
    .background(WindowConfigurator(floating: false))
    .sheet(
      isPresented: $store.showingCommandPalette,
      onDismiss: {
        if let task = pendingTask {
          editingTask = task
          pendingTask = nil
        }
      }
    ) {
      CommandPalette(
        store: store, onSelectTask: { pendingTask = $0 },
        onSelectProject: { section = .project($0) })
    }
    .sheet(isPresented: $store.showingImport) { ImportTasksView(store: store) }
    .alert(
      "Couldn't open Still link",
      isPresented: Binding(
        get: { store.handoffError != nil }, set: { if !$0 { store.handoffError = nil } })
    ) {
      Button("OK") { store.handoffError = nil }
    } message: {
      Text(store.handoffError ?? "")
    }
    .sheet(item: $editingTask) { task in TaskEditor(store: store, task: task) }
    .sheet(isPresented: $store.showingGuide) { GuideView() }
    .sheet(isPresented: $showingProjectPrompt) {
      ProjectEditor(
        store: store, name: $projectName, projectID: renamingProject, onSave: saveProject)
    }
    .confirmationDialog(
      "Remove project?",
      isPresented: Binding(
        get: { removingProject != nil }, set: { if !$0 { removingProject = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove project", role: .destructive) {
        guard let project = removingProject else { return }
        store.deleteProject(project.id)
        if section == .project(project.id) { section = .today }
        removingProject = nil
      }
      Button("Cancel", role: .cancel) { removingProject = nil }
    } message: {
      Text(
        "Tasks in \(removingProject?.name ?? "this project") will stay in Today or Inbox, without a project assignment."
      )
    }
    .onAppear {
      AppDelegate.reopen = {
        openWindow(id: "main")
        dismissWindow(id: "mini")
      }
      handleFocusRequest()
    }
    .onChange(of: store.focusRequest) { _, _ in handleFocusRequest() }
    .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
      if section == .history { section = .today }
      addingTask = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .captureThought)) { _ in
      showingNotes = true
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        StillMark(size: 19)
        Text("Still").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
        Spacer()
      }.padding(.horizontal, 21).padding(.top, 18).padding(.bottom, 28)
      VStack(spacing: 3) {
        navigationRow(
          "Today", icon: "sun.max", target: .today,
          count: store.state.tasks.filter { $0.isQueued && !$0.isComplete }.count)
        navigationRow(
          "Inbox", icon: "tray", target: .inbox,
          count: store.state.tasks.filter { !$0.isQueued && !$0.isComplete }.count)
        navigationRow("History", icon: "clock.arrow.circlepath", target: .history)
      }.padding(.horizontal, 10)
      HStack {
        Text("Projects").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
        Spacer()
        Button {
          renamingProject = nil
          projectName = ""
          showingProjectPrompt = true
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(IconButton()).help("New project").accessibilityLabel("New project")
      }.padding(.leading, 22).padding(.trailing, 10).padding(.top, 24).padding(.bottom, 3)
      ScrollView {
        VStack(spacing: 3) {
          ForEach(store.state.projects) { project in
            navigationRow(
              project.name, icon: "square.stack", target: .project(project.id),
              count: store.state.tasks.filter { $0.projectID == project.id && !$0.isComplete }.count
            )
            .contextMenu {
              Button("Rename project") {
                renamingProject = project.id
                projectName = project.name
                showingProjectPrompt = true
              }
              Button("Remove project", role: .destructive) {
                removingProject = project
              }
            }
          }
          if store.state.projects.isEmpty {
            Button {
              renamingProject = nil
              projectName = ""
              showingProjectPrompt = true
            } label: {
              Text("Create a project").font(.system(size: 12)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).padding(
                  .vertical, 7)
            }.buttonStyle(.plain)
          }
        }.padding(.horizontal, 10)
      }
      Spacer(minLength: 10)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(focusTotal).font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.ink)
          Text("focused today").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        Text(
          "\(store.state.todayCompletedCount(at: store.now)) completed \(store.state.todayCompletedCount(at: store.now) == 1 ? "session" : "sessions")"
        )
        .font(.system(size: 10)).foregroundStyle(Palette.muted)
      }.padding(21)
      Rectangle().fill(Palette.line).frame(height: 1)
      HStack {
        Button {
          store.showingGuide = true
        } label: {
          Image(systemName: "questionmark.circle")
        }
        .buttonStyle(IconButton()).help("Help and shortcuts").accessibilityLabel(
          "Help and shortcuts")
        Text(store.storageError == nil ? "Saved locally" : "Changes not saved").font(
          .system(size: 10)
        ).foregroundStyle(store.storageError == nil ? Palette.muted : Palette.accent)
        Spacer()
      }.padding(.horizontal, 12).frame(height: 43)
    }.background(Palette.panel)
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Button {
        store.showingCommandPalette = true
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").font(.system(size: 11))
          Text("Search").font(.system(size: 11))
          Text("⌘ K").font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.7))
        }
      }
      .buttonStyle(QuietButton()).help("Search tasks and projects (⌘K)").accessibilityLabel(
        "Search tasks and projects")
      Spacer()
      Button {
        showingNotes.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "note.text").font(.system(size: 12))
          Text("Notes").font(.system(size: 11))
          if !store.state.thoughts.isEmpty {
            Text("\(store.state.thoughts.filter { !$0.isDone }.count)").font(.system(size: 10))
              .foregroundStyle(Palette.muted)
          }
        }
      }.buttonStyle(QuietButton(selected: showingNotes)).help("Session notes (⌘⇧N)")
      Button {
        openWindow(id: "mini")
        dismissWindow(id: "main")
      } label: {
        Image(systemName: "pip.enter")
      }
      .buttonStyle(IconButton()).help("Mini player (⌘⇧M)").accessibilityLabel("Mini player")
    }.padding(.horizontal, 22).frame(height: 42)
  }

  private var workspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text(sectionTitle).font(.system(size: 24, weight: .semibold)).tracking(-0.7)
          Spacer()
          if section == .today {
            Text(store.now, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(
              .system(size: 12)
            ).foregroundStyle(Palette.muted)
          }
        }.padding(.bottom, 22)
        if section == .history {
          HistoryView(store: store)
        } else {
          if section == .today {
            SessionStrip(store: store).padding(.bottom, 24)
          }
          taskList
        }
      }.padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 30)
    }
  }

  private var taskList: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text(section == .today ? "Today’s tasks" : "Tasks").font(
          .system(size: 13, weight: .semibold))
        Text("\(visibleTasks.filter { !$0.isComplete }.count)").font(.system(size: 11))
          .foregroundStyle(Palette.muted)
        Spacer()
        Menu {
          Button("Import tasks…") { store.showingImport = true }
          Button("Copy as checklist") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              WorkExport.checklist(tasks: visibleTasks), forType: .string)
          }.disabled(visibleTasks.isEmpty)
          Button("Add task") { addingTask = true }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 12))
        }
        .tint(Palette.muted).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Task list options")
      }.padding(.bottom, 12)
      ForEach(visibleTasks.filter { !$0.isComplete }) { task in taskRow(task) }
      HStack(spacing: 12) {
        Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
          width: 17)
        TextField("Add a task…", text: $newTitle).textFieldStyle(.plain).font(.system(size: 13))
          .focused($addingTask).onSubmit(createTask).accessibilityLabel("New task title")
        if !newTitle.isEmpty {
          Button(action: createTask) {
            Image(systemName: "arrow.turn.down.left").font(.system(size: 11))
          }
          .buttonStyle(IconButton()).accessibilityLabel("Create task")
        } else {
          Text("⌘ N").font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.7))
        }
      }.padding(.horizontal, 12).frame(minHeight: 46)
        .background(addingTask ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6).stroke(addingTask ? Palette.line : .clear, lineWidth: 1)
        )
        .padding(.top, 4)
      if visibleTasks.isEmpty {
        Text(
          section == .inbox
            ? "Keep tasks here until you're ready to add them to Today."
            : "Add tasks here, or move them from Inbox when you're ready."
        )
        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
        .padding(.leading, 41).padding(.top, 8)
      }
      let completed = visibleTasks.filter(\.isComplete)
      if !completed.isEmpty {
        Button {
          showingCompleted.toggle()
        } label: {
          HStack(spacing: 7) {
            Image(systemName: showingCompleted ? "chevron.down" : "chevron.right").font(
              .system(size: 9))
            Text("Completed (\(completed.count))").font(.system(size: 12))
          }
        }.buttonStyle(QuietButton()).padding(.top, 20)
        if showingCompleted { ForEach(completed) { task in taskRow(task) } }
      }
      if let removed = store.recentlyDeletedTask {
        HStack {
          Text("Removed \(removed.title)").font(.system(size: 11)).lineLimit(1)
          Spacer()
          Button("Undo", action: store.undoDeleteTask).font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 6)).padding(
          .top, 14)
      }
    }
  }

  private func taskRow(_ task: TaskItem) -> some View {
    HStack(spacing: 12) {
      Button {
        store.toggleTaskComplete(task.id)
      } label: {
        Image(systemName: task.isComplete ? "checkmark.square.fill" : "square")
          .font(.system(size: 16, weight: .light)).foregroundStyle(
            task.isComplete ? Palette.green : Palette.muted.opacity(0.6))
      }.buttonStyle(.plain).help(task.isComplete ? "Reopen task" : "Complete task")
        .accessibilityLabel(task.isComplete ? "Reopen \(task.title)" : "Complete \(task.title)")
      Button {
        editingTask = task
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          Text(task.title).font(
            .system(size: 13, weight: store.selectedTask?.id == task.id ? .medium : .regular)
          )
          .foregroundStyle(task.isComplete ? Palette.muted : Palette.ink).strikethrough(
            task.isComplete
          ).lineLimit(2)
          if let project = store.state.projects.first(where: { $0.id == task.projectID }),
            section != .project(project.id)
          {
            Text(project.name).font(.system(size: 10)).foregroundStyle(Palette.muted)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).help("Edit task")
      if !task.links.isEmpty {
        Button {
          editingTask = task
        } label: {
          Image(systemName: "link").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain).help("\(task.links.count) references").accessibilityLabel(
          "References for \(task.title)")
      }
      if !task.notes.isEmpty {
        Button {
          editingTask = task
        } label: {
          Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain).help("Task notes").accessibilityLabel("Notes for \(task.title)")
      }
      Text("\(task.estimateMinutes)m").font(.system(size: 11, design: .monospaced)).foregroundStyle(
        Palette.muted)
      if !task.isComplete {
        Button {
          if store.prepareTask(task.id) {
            section = .today
            store.primaryAction()
          }
        } label: {
          Image(systemName: "play.fill").font(.system(size: 10))
        }
        .buttonStyle(IconButton()).disabled(store.isActive).help(
          store.isActive ? "End the current session before starting another" : "Focus on this task"
        )
        .accessibilityLabel("Focus on \(task.title)")
      }
      Menu {
        Button("Edit task") { editingTask = task }
        Button("Copy task brief") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(
            WorkExport.brief(
              task: task, project: store.state.projects.first { $0.id == task.projectID }),
            forType: .string)
        }
        if !task.isComplete {
          Button(task.isQueued ? "Move to Inbox" : "Add to Today") {
            store.queueTask(task.id, queued: !task.isQueued)
          }
          Button("Move to top") {
            store.moveTask(task.id, before: visibleTasks.first(where: { !$0.isComplete })?.id)
          }
          Button("Move to bottom") { store.moveTask(task.id, before: nil) }
        }
        Divider()
        Button("Remove task", role: .destructive) { store.deleteTask(task.id) }
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
          width: 18)
      }
      .tint(Palette.muted).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel(
        "Actions for \(task.title)")
    }.padding(.horizontal, 12).padding(.vertical, 12)
      .background(
        store.selectedTask?.id == task.id && !task.isComplete
          ? Palette.accentSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 6)
      )
      .overlay(alignment: .bottom) {
        Rectangle().fill(Palette.line.opacity(0.65)).frame(height: 1).padding(.leading, 41)
      }
  }

  private var bottomBar: some View {
    VStack(spacing: 0) {
      if let message = store.storageError {
        Text(message).font(.system(size: 11)).foregroundStyle(Palette.accent).textSelection(
          .enabled
        )
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accentSoft)
      }
      Rectangle().fill(Palette.line).frame(height: 1)
      HStack {
        SoundscapeView(audio: store.audio)
        Spacer(minLength: 4)
        Text("⌘ ↵  Start / pause").font(.system(size: 10)).foregroundStyle(Palette.muted)
      }.padding(.horizontal, 22).frame(height: 43)
    }
  }

  private func navigationRow(
    _ title: String, icon: String, target: WorkspaceSection, count: Int = 0
  ) -> some View {
    Button {
      section = target
    } label: {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 13)).frame(width: 16).foregroundStyle(
          section == target ? Palette.ink : Palette.muted)
        Text(title).font(.system(size: 12, weight: section == target ? .medium : .regular))
          .lineLimit(1)
        Spacer(minLength: 4)
        if count > 0 { Text("\(count)").font(.system(size: 10)).foregroundStyle(Palette.muted) }
      }.foregroundStyle(Palette.ink).padding(.horizontal, 11).frame(height: 33)
        .background(
          section == target ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 6)
        ).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityAddTraits(section == target ? .isSelected : [])
  }

  private var visibleTasks: [TaskItem] {
    store.state.tasks.filter { task in
      switch section {
      case .today: task.isQueued
      case .inbox: !task.isQueued
      case .history: false
      case .project(let id): task.projectID == id
      }
    }
  }
  private var sectionTitle: String {
    switch section {
    case .today: "Today"
    case .inbox: "Inbox"
    case .history: "History"
    case .project(let id): store.state.projects.first(where: { $0.id == id })?.name ?? "Project"
    }
  }
  private var focusTotal: String {
    let minutes = Int(store.state.todayFocusSeconds(at: store.now) / 60)
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
  private func handleFocusRequest() {
    guard let request = store.focusRequest else { return }
    switch request {
    case .task:
      if section == .history { section = .today }
      addingTask = true
    case .today:
      section = .today
    case .note:
      showingNotes = true
      NotificationCenter.default.post(name: .captureThought, object: nil)
    }
    store.focusRequest = nil
  }
  private func createTask() {
    let projectID: UUID? = if case .project(let id) = section { id } else { nil }
    if let id = store.createTask(title: newTitle, projectID: projectID, estimateMinutes: 25) {
      if section == .inbox { store.queueTask(id, queued: false) }
      newTitle = ""
    }
  }
  private func saveProject() {
    if let id = renamingProject {
      store.renameProject(id, name: projectName)
    } else if let id = store.addProject(projectName) {
      section = .project(id)
    }
    projectName = ""
    renamingProject = nil
  }

}

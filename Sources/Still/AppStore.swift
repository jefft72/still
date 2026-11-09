import AppKit
import Combine
import Foundation
import StillCore

@MainActor
final class AppStore: ObservableObject {
  enum FocusRequest { case task, note, today }
  @Published var focusRequest: FocusRequest?
  @Published private(set) var state: StillState
  @Published var now: Date
  @Published var storageError: String?
  @Published var showingGuide = false
  @Published var showingCommandPalette = false
  @Published var showingImport = false
  @Published var handoffError: String?
  @Published var thoughtDraft = ""
  @Published private(set) var recentlyDeletedTask: TaskItem?
  let audio = AmbientAudio()
  private var repository: StateRepository?
  private var canSave = true
  private let clock: () -> Date
  private var ticker: AnyCancellable?
  private var sleepObserver: AnyCancellable?
  private var audioPreferences: Set<AnyCancellable> = []
  private var deletedTaskIndex: Int?

  init(
    repository: StateRepository? = nil,
    defaults: UserDefaults = .standard,
    clock: @escaping () -> Date = Date.init,
    automaticTicking: Bool = true
  ) {
    self.clock = clock
    now = clock()
    state = StillState()
    do {
      if let repository {
        self.repository = repository
      } else if let directory = ProcessInfo.processInfo.environment["STILL_DATA_DIR"] {
        self.repository = StateRepository(
          fileURL: URL(fileURLWithPath: directory).appendingPathComponent("state.json"))
      } else {
        self.repository = try StateRepository.applicationDefault()
      }
      state = try self.repository?.load() ?? StillState()
    } catch {
      self.repository = nil
      canSave = false
      storageError =
        "Still couldn't open its saved data. Your original file is safe. This session won't be saved. \(error.localizedDescription)"
    }
    restoreAudioPreferences(from: defaults)
    if state.reconcile(at: now) { persist() }
    if automaticTicking {
      ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink {
        [weak self] _ in
        guard let self else { return }
        self.tick(self.clock())
      }
      sleepObserver = NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didWakeNotification
      )
      .sink { [weak self] _ in
        guard let self else { return }
        self.tick(self.clock())
      }
    }
  }

  var timeString: String {
    let seconds = Int(ceil(state.session.remaining(at: now)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  var isActive: Bool { state.session.phase == .running || state.session.phase == .paused }
  var selectedTask: TaskItem? {
    state.tasks.first { $0.id == state.session.taskID }
  }
  var intention: String {
    state.session.intention.isEmpty ? "Untitled session" : state.session.intention
  }
  var actionTitle: String {
    switch state.session.phase {
    case .idle: return "Start session"
    case .running: return "Pause session"
    case .paused: return "Resume session"
    case .finished: return "Start another session"
    }
  }
  var actionSymbol: String { state.session.phase == .running ? "pause.fill" : "play.fill" }

  func tick(_ date: Date) {
    now = date
    if state.reconcile(at: date) {
      audio.stop()
      persist()
    }
  }

  func primaryAction() {
    now = clock()
    // A click on Pause may arrive after the deadline but before the next tick.
    // Complete that session without treating the stale click as a new Start.
    if state.reconcile(at: now) {
      audio.stop()
      persist()
      return
    }
    switch state.session.phase {
    case .idle, .finished: state.start(at: now)
    case .running: state.pause(at: now)
    case .paused: state.resume(at: now)
    }
    persist()
  }

  func reset() {
    now = clock()
    state.reconcile(at: now)
    state.reset()
    audio.stop()
    persist()
  }

  func setIntention(_ text: String) {
    guard !isActive else { return }
    state.session.intention = text
    persist()
  }

  func setDuration(_ minutes: Int) {
    state.session.setDuration(Double(minutes) * 60)
    persist()
  }

  @discardableResult
  func addThought(_ text: String) -> Bool {
    guard state.addThought(text, at: clock()) else { return false }
    persist()
    return true
  }

  func captureThought() {
    if addThought(thoughtDraft) { thoughtDraft = "" }
  }

  func toggleThought(_ id: UUID) {
    state.toggleThought(id: id)
    persist()
  }

  func deleteThought(_ id: UUID) {
    state.deleteThought(id: id)
    persist()
  }

  @discardableResult
  func prepareTask(_ id: UUID) -> Bool {
    now = clock()
    tick(now)
    guard state.prepareTask(id: id) else { return false }
    persist()
    return true
  }

  @discardableResult
  func createTask(title: String, projectID: UUID? = nil, estimateMinutes: Int = 25) -> UUID? {
    let id = state.addTask(
      title: title, projectID: projectID, estimateMinutes: estimateMinutes, at: clock())
    if id != nil { persist() }
    return id
  }

  func handleURL(_ url: URL) {
    do {
      switch try StillURLAction.parse(url) {
      case .note(let text):
        _ = addThought(text)
        focusRequest = .note
      case .task(let title, let notes, let projectName, let minutes, let reference):
        let projectID: UUID?
        if let name = projectName {
          projectID =
            state.projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            ?? state.addProject(name: name, at: clock())
        } else {
          projectID = nil
        }
        if let id = state.addTask(
          title: title, projectID: projectID, estimateMinutes: minutes, at: clock()),
          var task = state.tasks.first(where: { $0.id == id })
        {
          task.notes = notes
          if let reference {
            task.links = [
              TaskLink(title: reference.host ?? "Reference", url: reference.absoluteString)
            ]
          }
          _ = state.updateTask(task)
          persist()
        }
        focusRequest = .today
      }
      handoffError = nil
    } catch {
      handoffError = error.localizedDescription
      focusRequest = .today
    }
  }

  func importTasks(_ items: [ImportedTask], projectID: UUID?, queued: Bool) {
    let timestamp = clock()
    for item in items {
      guard let id = state.addTask(title: item.title, projectID: projectID, at: timestamp) else {
        continue
      }
      state.queueTask(id: id, queued: queued)
      if item.isComplete { state.toggleTaskComplete(id: id, at: timestamp) }
    }
    persist()
    focusRequest = .today
  }

  func updateTask(_ task: TaskItem) {
    guard state.updateTask(task) else { return }
    if state.session.taskID == task.id && !isActive {
      state.prepareTask(id: task.id)
    }
    persist()
  }

  func toggleTaskComplete(_ id: UUID) {
    state.toggleTaskComplete(id: id, at: clock())
    persist()
  }

  func deleteTask(_ id: UUID) {
    guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
    recentlyDeletedTask = state.tasks[index]
    deletedTaskIndex = index
    state.deleteTask(id: id)
    persist()
  }

  func undoDeleteTask() {
    guard var task = recentlyDeletedTask, !state.tasks.contains(where: { $0.id == task.id }) else {
      return
    }
    if let projectID = task.projectID, !state.projects.contains(where: { $0.id == projectID }) {
      task.projectID = nil
    }
    var tasks = state.tasks
    tasks.insert(task, at: min(deletedTaskIndex ?? tasks.count, tasks.count))
    state = StillState(
      session: state.session, thoughts: state.thoughts, history: state.history,
      tasks: tasks, projects: state.projects)
    recentlyDeletedTask = nil
    deletedTaskIndex = nil
    persist()
  }

  func queueTask(_ id: UUID, queued: Bool) {
    state.queueTask(id: id, queued: queued)
    persist()
  }

  func moveTask(_ id: UUID, before: UUID?) {
    state.moveTask(id: id, before: before)
    persist()
  }

  @discardableResult
  func addProject(_ name: String) -> UUID? {
    let id = state.addProject(name: name, at: clock())
    if id != nil { persist() }
    return id
  }

  func renameProject(_ id: UUID, name: String) {
    if state.renameProject(id: id, name: name) { persist() }
  }

  func deleteProject(_ id: UUID) {
    state.deleteProject(id: id)
    persist()
  }

  private func restoreAudioPreferences(from defaults: UserDefaults) {
    if let saved = defaults.object(forKey: "audio.volume") as? Double, saved.isFinite {
      audio.volume = min(max(saved, 0), 1)
    }
    if let saved = defaults.string(forKey: "audio.soundscape"),
      let soundscape = AmbientAudio.Soundscape(rawValue: saved)
    {
      audio.soundscape = soundscape
    }
    audio.$volume.removeDuplicates().sink { value in
      defaults.set(value.isFinite ? min(max(value, 0), 1) : 0.35, forKey: "audio.volume")
    }.store(in: &audioPreferences)
    audio.$soundscape.removeDuplicates().sink { value in
      defaults.set(value.rawValue, forKey: "audio.soundscape")
    }.store(in: &audioPreferences)
  }

  private func persist() {
    guard canSave, let repository else { return }
    do {
      try repository.save(state)
      storageError = nil
    } catch {
      storageError = "Your latest changes couldn't be saved. \(error.localizedDescription)"
    }
  }
}

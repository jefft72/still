import Foundation

public struct Project: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var createdAt: Date

  public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
  }
}

public struct TaskLink: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var url: String

  public init(id: UUID = UUID(), title: String = "", url: String) {
    self.id = id
    self.title = title
    self.url = url
  }
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var notes: String
  public var projectID: UUID?
  public var estimateMinutes: Int
  public var createdAt: Date
  public var completedAt: Date?
  public var isQueued: Bool
  public var links: [TaskLink]

  public var isComplete: Bool { completedAt != nil }

  public init(
    id: UUID = UUID(), title: String, notes: String = "", projectID: UUID? = nil,
    estimateMinutes: Int = 25, createdAt: Date = Date(), completedAt: Date? = nil,
    isQueued: Bool = true, links: [TaskLink] = []
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.projectID = projectID
    self.estimateMinutes = min(180, max(1, estimateMinutes))
    self.createdAt = createdAt
    self.completedAt = completedAt
    self.isQueued = isQueued
    self.links = links
  }
}

extension StillState {
  var isValidWorkspace: Bool {
    let projectIDs = Set(projects.map(\.id))
    guard projectIDs.count == projects.count,
      Set(tasks.map(\.id)).count == tasks.count,
      projects.allSatisfy({
        !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && $0.createdAt.timeIntervalSince1970.isFinite
      })
    else { return false }
    return tasks.allSatisfy { task in
      !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (1...180).contains(task.estimateMinutes)
        && task.createdAt.timeIntervalSince1970.isFinite
        && task.completedAt?.timeIntervalSince1970.isFinite != false
        && (task.projectID.map { projectIDs.contains($0) } ?? true)
        && Set(task.links.map(\.id)).count == task.links.count
        && task.links.allSatisfy { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
  }

  public var queuedTasks: [TaskItem] { tasks.filter { $0.isQueued && !$0.isComplete } }
  public var unfinishedTasks: [TaskItem] { tasks.filter { !$0.isComplete } }

  @discardableResult
  public mutating func addTask(
    title: String, projectID: UUID? = nil, estimateMinutes: Int = 25, at now: Date = Date()
  ) -> UUID? {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, projectID == nil || projects.contains(where: { $0.id == projectID })
    else { return nil }
    let task = TaskItem(
      title: title, projectID: projectID, estimateMinutes: estimateMinutes, createdAt: now)
    tasks.append(task)
    return task.id
  }

  @discardableResult
  public mutating func updateTask(_ task: TaskItem) -> Bool {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }),
      task.projectID == nil || projects.contains(where: { $0.id == task.projectID }),
      Set(task.links.map(\.id)).count == task.links.count,
      task.links.allSatisfy({ !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else { return false }
    var updated = task
    updated.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !updated.title.isEmpty else { return false }
    updated.estimateMinutes = min(180, max(1, task.estimateMinutes))
    tasks[index] = updated
    return true
  }

  public mutating func toggleTaskComplete(id: UUID, at now: Date = Date()) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].completedAt = tasks[index].completedAt == nil ? now : nil
  }

  public mutating func deleteTask(id: UUID) {
    tasks.removeAll { $0.id == id }
  }

  public mutating func queueTask(id: UUID, queued: Bool) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].isQueued = queued
  }

  /// Reorder one task without changing the relative order of every other task.
  public mutating func moveTask(id: UUID, before targetID: UUID?) {
    guard id != targetID, let index = tasks.firstIndex(where: { $0.id == id }),
      targetID == nil || tasks.contains(where: { $0.id == targetID })
    else { return }
    let task = tasks.remove(at: index)
    if let targetID, let target = tasks.firstIndex(where: { $0.id == targetID }) {
      tasks.insert(task, at: target)
    } else {
      tasks.append(task)
    }
  }

  @discardableResult
  public mutating func addProject(name: String, at now: Date = Date()) -> UUID? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
      !projects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else { return nil }
    let project = Project(name: name, createdAt: now)
    projects.append(project)
    return project.id
  }

  @discardableResult
  public mutating func renameProject(id: UUID, name: String) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let index = projects.firstIndex(where: { $0.id == id }),
      !projects.contains(where: {
        $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else { return false }
    projects[index].name = name
    return true
  }

  public mutating func deleteProject(id: UUID) {
    projects.removeAll { $0.id == id }
    for index in tasks.indices where tasks[index].projectID == id {
      tasks[index].projectID = nil
    }
  }

  /// Selecting work prepares its next session; completing a session does not finish the task.
  @discardableResult
  public mutating func prepareTask(id: UUID) -> Bool {
    guard session.phase == .idle || session.phase == .finished,
      let task = tasks.first(where: { $0.id == id }), !task.isComplete
    else { return false }
    session = FocusSession(
      intention: task.title, duration: TimeInterval(task.estimateMinutes * 60),
      taskID: task.id, projectID: task.projectID)
    return true
  }
}

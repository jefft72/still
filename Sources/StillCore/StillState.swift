import Foundation

public struct Thought: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var text: String
  public let createdAt: Date
  public var isDone: Bool

  public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), isDone: Bool = false) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
    self.isDone = isDone
  }
}

public struct SessionRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let intention: String
  public let duration: TimeInterval
  public let startedAt: Date
  public let completedAt: Date
  public let taskID: UUID?
  public let projectID: UUID?

  public init(
    id: UUID = UUID(), intention: String, duration: TimeInterval, startedAt: Date,
    completedAt: Date,
    taskID: UUID? = nil, projectID: UUID? = nil
  ) {
    self.id = id
    self.intention = intention
    self.duration = duration
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.taskID = taskID
    self.projectID = projectID
  }
}

public struct StillState: Codable, Equatable, Sendable {
  public var session: FocusSession
  public private(set) var thoughts: [Thought]
  public private(set) var history: [SessionRecord]
  public internal(set) var tasks: [TaskItem]
  public internal(set) var projects: [Project]

  public init(
    session: FocusSession = FocusSession(), thoughts: [Thought] = [], history: [SessionRecord] = [],
    tasks: [TaskItem] = [], projects: [Project] = []
  ) {
    self.session = session
    self.thoughts = thoughts
    self.history = history
    self.tasks = tasks
    self.projects = projects
  }

  private enum CodingKeys: String, CodingKey {
    case session, thoughts, history, tasks, projects
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    session = try container.decode(FocusSession.self, forKey: .session)
    thoughts = try container.decode([Thought].self, forKey: .thoughts)
    history = try container.decode([SessionRecord].self, forKey: .history)
    tasks = try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
    projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
  }

  public mutating func start(at now: Date = Date()) {
    reconcile(at: now)
    session.start(at: now)
  }

  public mutating func pause(at now: Date = Date()) {
    reconcile(at: now)
    session.pause(at: now)
  }

  public mutating func resume(at now: Date = Date()) {
    session.resume(at: now)
  }

  /// Discard an unfinished session without recording focus time.
  public mutating func reset() {
    session.reset()
  }

  /// Returns true only on the transition to finished, including after relaunch.
  @discardableResult
  public mutating func reconcile(at now: Date = Date()) -> Bool {
    guard session.phase == .running,
      let deadline = session.deadline,
      deadline <= now,
      let startedAt = session.startedAt
    else { return false }
    if !history.contains(where: { $0.id == session.id }) {
      // A wall-clock correction while paused can put completion before the original start.
      // Keep the actual completion date and ensure its interval contains the focused duration.
      let recordStart = min(startedAt, deadline.addingTimeInterval(-session.duration))
      history.insert(
        SessionRecord(
          id: session.id,
          intention: session.intention,
          duration: session.duration,
          startedAt: recordStart,
          completedAt: deadline,
          taskID: session.taskID,
          projectID: session.projectID
        ), at: 0)
    }
    session.finish()
    return true
  }

  @discardableResult
  public mutating func addThought(_ text: String, at now: Date = Date()) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    thoughts.insert(Thought(text: trimmed, createdAt: now), at: 0)
    return true
  }

  public mutating func toggleThought(id: UUID) {
    guard let index = thoughts.firstIndex(where: { $0.id == id }) else { return }
    thoughts[index].isDone.toggle()
  }

  public mutating func deleteThought(id: UUID) {
    thoughts.removeAll { $0.id == id }
  }

  public func todayCompletedCount(at now: Date = Date(), calendar: Calendar = .current) -> Int {
    history.filter { calendar.isDate($0.completedAt, inSameDayAs: now) }.count
  }

  public func todayFocusSeconds(at now: Date = Date(), calendar: Calendar = .current)
    -> TimeInterval
  {
    history.filter { calendar.isDate($0.completedAt, inSameDayAs: now) }.reduce(0) {
      $0 + $1.duration
    }
  }
}

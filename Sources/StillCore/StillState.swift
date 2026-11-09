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

  public init(
    id: UUID = UUID(), intention: String, duration: TimeInterval, startedAt: Date, completedAt: Date
  ) {
    self.id = id
    self.intention = intention
    self.duration = duration
    self.startedAt = startedAt
    self.completedAt = completedAt
  }
}

public struct StillState: Codable, Equatable, Sendable {
  public var session: FocusSession
  public private(set) var thoughts: [Thought]
  public private(set) var history: [SessionRecord]

  public init(
    session: FocusSession = FocusSession(), thoughts: [Thought] = [], history: [SessionRecord] = []
  ) {
    self.session = session
    self.thoughts = thoughts
    self.history = history
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
      history.insert(
        SessionRecord(
          id: session.id,
          intention: session.intention,
          duration: session.duration,
          startedAt: startedAt,
          completedAt: deadline
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

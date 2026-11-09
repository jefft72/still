import Foundation

public enum SessionPhase: String, Codable, CaseIterable, Sendable {
  case idle, running, paused, finished
}

/// A wall-clock deadline keeps a running session accurate through sleep and relaunch.
public struct FocusSession: Codable, Equatable, Sendable {
  public private(set) var id: UUID
  public var intention: String
  public private(set) var duration: TimeInterval
  public private(set) var phase: SessionPhase
  public private(set) var startedAt: Date?
  public private(set) var deadline: Date?
  private var pausedRemaining: TimeInterval

  public init(intention: String = "", duration: TimeInterval = 25 * 60) {
    id = UUID()
    self.intention = intention
    self.duration = Self.validDuration(duration)
    phase = .idle
    startedAt = nil
    deadline = nil
    pausedRemaining = self.duration
  }

  public func remaining(at now: Date = Date()) -> TimeInterval {
    switch phase {
    case .idle: return duration
    case .running: return min(duration, max(0, (deadline ?? now).timeIntervalSince(now)))
    case .paused: return pausedRemaining
    case .finished: return 0
    }
  }

  public func progress(at now: Date = Date()) -> Double {
    min(1, max(0, 1 - remaining(at: now) / duration))
  }

  public mutating func setDuration(_ seconds: TimeInterval) {
    guard phase == .idle || phase == .finished else { return }
    duration = Self.validDuration(seconds)
    if phase == .finished { reset() }
    pausedRemaining = duration
  }

  mutating func start(at now: Date) {
    guard phase == .idle || phase == .finished else { return }
    id = UUID()
    intention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
    phase = .running
    startedAt = now
    deadline = now.addingTimeInterval(duration)
    pausedRemaining = duration
  }

  mutating func pause(at now: Date) {
    guard phase == .running else { return }
    pausedRemaining = remaining(at: now)
    deadline = nil
    phase = .paused
  }

  mutating func resume(at now: Date) {
    guard phase == .paused else { return }
    deadline = now.addingTimeInterval(pausedRemaining)
    phase = .running
  }

  mutating func finish() {
    phase = .finished
    pausedRemaining = 0
  }

  mutating func reset() {
    self = FocusSession(intention: intention, duration: duration)
  }

  var isValidPersistedState: Bool {
    guard duration.isFinite, (1...10_800).contains(duration),
      pausedRemaining.isFinite, (0...duration).contains(pausedRemaining),
      startedAt?.timeIntervalSince1970.isFinite != false,
      deadline?.timeIntervalSince1970.isFinite != false
    else { return false }
    switch phase {
    case .idle:
      return startedAt == nil && deadline == nil && pausedRemaining == duration
    case .running:
      return startedAt != nil && deadline != nil && pausedRemaining > 0
    case .paused:
      return startedAt != nil && deadline == nil && pausedRemaining > 0
    case .finished:
      return startedAt != nil && deadline != nil && pausedRemaining == 0
    }
  }

  private static func validDuration(_ duration: TimeInterval) -> TimeInterval {
    guard duration.isFinite else { return 25 * 60 }
    return min(180 * 60, max(1, duration))
  }
}

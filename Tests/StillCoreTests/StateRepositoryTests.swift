import Foundation
import XCTest

@testable import StillCore

final class StateRepositoryTests: XCTestCase {
  private var folder: URL!
  private var repository: StateRepository!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    repository = StateRepository(fileURL: folder.appendingPathComponent("nested/state.json"))
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
  }

  func testMissingFileReturnsFreshStateWithoutWriting() throws {
    let state = try repository.load()
    XCTAssertEqual(state.session.phase, .idle)
    XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
  }

  func testAtomicSaveCreatesDirectoryAndRoundTripsEntireState() throws {
    var state = StillState(session: FocusSession(intention: "Write", duration: 60))
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    state.start(at: start)
    state.reconcile(at: start.addingTimeInterval(60))
    state.addThought("Check the draft", at: start)
    state.toggleThought(id: state.thoughts[0].id)
    try repository.save(state)
    XCTAssertEqual(try repository.load(), state)
    state.start(at: start.addingTimeInterval(120))
    try repository.save(state)
    XCTAssertEqual(try repository.load(), state)
  }

  func testCorruptDataIsReportedAndPreserved() throws {
    try FileManager.default.createDirectory(
      at: repository.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let damaged = Data("{damaged".utf8)
    try damaged.write(to: repository.fileURL)
    XCTAssertThrowsError(try repository.load())
    XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
  }

  func testNewerFormatIsReportedBeforeDecodingPayloadAndPreserved() throws {
    try FileManager.default.createDirectory(
      at: repository.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let newer = Data("{\"version\":3,\"state\":{\"newField\":true}}".utf8)
    try newer.write(to: repository.fileURL)
    XCTAssertThrowsError(try repository.load()) { error in
      XCTAssertEqual(error as? StateRepository.StorageError, .unsupportedVersion(3))
    }
    XCTAssertEqual(try Data(contentsOf: repository.fileURL), newer)
  }

  func testInvalidRunningSessionIsRejected() throws {
    var state = StillState(session: FocusSession(duration: 60))
    state.start()
    try repository.save(state)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as? [String: Any])
    var payload = try XCTUnwrap(envelope["state"] as? [String: Any])
    var session = try XCTUnwrap(payload["session"] as? [String: Any])
    session.removeValue(forKey: "deadline")
    payload["session"] = session
    envelope["state"] = payload
    try JSONSerialization.data(withJSONObject: envelope).write(to: repository.fileURL)
    XCTAssertThrowsError(try repository.load()) { error in
      XCTAssertEqual(error as? StateRepository.StorageError, .invalidSession)
    }
  }
  func testPausedSessionRejectsNegativeOrExcessRemainingTime() throws {
    for remaining in [-1.0, 61.0, 0.0] {
      var state = StillState(session: FocusSession(duration: 60))
      let start = Date(timeIntervalSince1970: 1_800_000_000)
      state.start(at: start)
      state.pause(at: start.addingTimeInterval(10))
      try repository.save(state)
      try editSession { $0["pausedRemaining"] = remaining }
      XCTAssertThrowsError(try repository.load())
    }
  }

  func testPausedSessionRequiresStartAndMustNotHaveDeadline() throws {
    var state = StillState(session: FocusSession(duration: 60))
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    state.start(at: start)
    state.pause(at: start.addingTimeInterval(10))
    try repository.save(state)
    try editSession { $0.removeValue(forKey: "startedAt") }
    XCTAssertThrowsError(try repository.load())
    try repository.save(state)
    try editSession { $0["deadline"] = 1_800_000_000.0 }
    XCTAssertThrowsError(try repository.load())
  }

  func testDuplicateHistoryAndThoughtIDsAreRejected() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let record = SessionRecord(
      intention: "Write", duration: 60, startedAt: date, completedAt: date.addingTimeInterval(60))
    try repository.save(StillState(history: [record, record]))
    XCTAssertThrowsError(try repository.load())
    let thought = Thought(text: "Later")
    try repository.save(StillState(thoughts: [thought, thought]))
    XCTAssertThrowsError(try repository.load())
  }

  func testNegativeHistoryDurationAndReversedDatesAreRejected() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    for record in [
      SessionRecord(
        intention: "Write", duration: -60, startedAt: date, completedAt: date.addingTimeInterval(60)
      ),
      SessionRecord(
        intention: "Write", duration: 60, startedAt: date, completedAt: date.addingTimeInterval(-60)
      ),
    ] {
      try repository.save(StillState(history: [record]))
      XCTAssertThrowsError(try repository.load())
    }
  }

  func testFutureHistoryDoesNotDependOnDeviceCurrentClock() throws {
    // Device clock corrections must not make otherwise valid history unreadable.
    let date = Date(timeIntervalSince1970: 4_000_000_000)
    let record = SessionRecord(
      intention: "Write", duration: 60, startedAt: date, completedAt: date.addingTimeInterval(60))
    let state = StillState(history: [record])
    try repository.save(state)
    XCTAssertEqual(try repository.load(), state)
  }

  private func editSession(_ edit: (inout [String: Any]) -> Void) throws {
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as? [String: Any])
    var payload = try XCTUnwrap(envelope["state"] as? [String: Any])
    var session = try XCTUnwrap(payload["session"] as? [String: Any])
    edit(&session)
    payload["session"] = session
    envelope["state"] = payload
    try JSONSerialization.data(withJSONObject: envelope).write(to: repository.fileURL)
  }

  func testLegacyVersionOneMigratesWithoutLosingSessionsOrThoughts() throws {
    var state = StillState(session: FocusSession(intention: "Keep this", duration: 60))
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    state.start(at: date)
    state.reconcile(at: date.addingTimeInterval(60))
    state.addThought("Do not lose this", at: date)
    try repository.save(state)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as? [String: Any])
    envelope["version"] = 1
    var payload = try XCTUnwrap(envelope["state"] as? [String: Any])
    payload.removeValue(forKey: "tasks")
    payload.removeValue(forKey: "projects")
    envelope["state"] = payload
    let legacyData = try JSONSerialization.data(withJSONObject: envelope)
    try legacyData.write(to: repository.fileURL)
    let restored = try repository.load()
    XCTAssertEqual(restored, state)
    XCTAssertEqual(try Data(contentsOf: repository.fileURL), legacyData)
    try repository.save(restored)
    let updated = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as? [String: Any])
    XCTAssertEqual(updated["version"] as? Int, 2)
  }

  func testRepositoryRejectsDanglingTaskProjectsButAcceptsHistoricalOrphans() throws {
    let missingProject = UUID()
    try repository.save(StillState(tasks: [TaskItem(title: "Work", projectID: missingProject)]))
    XCTAssertThrowsError(try repository.load())
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let record = SessionRecord(
      intention: "Past work", duration: 60, startedAt: date,
      completedAt: date.addingTimeInterval(60), taskID: UUID(), projectID: missingProject)
    let state = StillState(history: [record])
    try repository.save(state)
    XCTAssertEqual(try repository.load(), state)
  }

}

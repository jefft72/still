import Foundation
import XCTest

@testable import StillCore

final class StillStateTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  func testSessionDeadlineSurvivesEncodeAndRelaunch() throws {
    var state = StillState(
      session: FocusSession(intention: "Ship the small thing", duration: 1_500))
    state.start(at: start)
    let data = try JSONEncoder().encode(state)
    var restored = try JSONDecoder().decode(StillState.self, from: data)
    XCTAssertEqual(restored.session.remaining(at: start.addingTimeInterval(300)), 1_200)
    XCTAssertEqual(
      restored.session.progress(at: start.addingTimeInterval(300)), 0.2, accuracy: 0.0001)
    XCTAssertTrue(restored.reconcile(at: start.addingTimeInterval(2_000)))
    XCTAssertEqual(restored.session.phase, .finished)
    XCTAssertEqual(restored.history.count, 1)
    XCTAssertEqual(restored.history[0].completedAt, start.addingTimeInterval(1_500))
    XCTAssertEqual(restored.history[0].intention, "Ship the small thing")
    XCTAssertFalse(restored.reconcile(at: start.addingTimeInterval(3_000)))
    XCTAssertEqual(restored.history.count, 1)
  }

  func testPauseExcludesTimeAwayAndSurvivesRelaunch() throws {
    var state = StillState(session: FocusSession(duration: 600))
    state.start(at: start)
    state.pause(at: start.addingTimeInterval(120))
    XCTAssertEqual(state.session.phase, .paused)
    XCTAssertEqual(state.session.remaining(at: start.addingTimeInterval(12_000)), 480)
    let data = try JSONEncoder().encode(state)
    state = try JSONDecoder().decode(StillState.self, from: data)
    state.resume(at: start.addingTimeInterval(3_000))
    XCTAssertEqual(state.session.remaining(at: start.addingTimeInterval(3_060)), 420)
    XCTAssertTrue(state.reconcile(at: start.addingTimeInterval(3_480)))
    XCTAssertEqual(state.history[0].duration, 600)
    XCTAssertEqual(state.history[0].completedAt, start.addingTimeInterval(3_480))
  }

  func testPauseAfterDeadlineRecordsCompletionInsteadOfZeroTimePause() {
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: start)
    state.pause(at: start.addingTimeInterval(61))
    XCTAssertEqual(state.session.phase, .finished)
    XCTAssertEqual(state.history.count, 1)
    state.resume(at: start.addingTimeInterval(62))
    XCTAssertEqual(state.session.phase, .finished)
  }

  func testResetDiscardsPartialSessionAndKeepsIntentionAndDuration() {
    var state = StillState(session: FocusSession(intention: "Finish", duration: 900))
    state.start(at: start)
    state.pause(at: start.addingTimeInterval(100))
    state.reset()
    XCTAssertEqual(state.session.phase, .idle)
    XCTAssertEqual(state.session.intention, "Finish")
    XCTAssertEqual(state.session.duration, 900)
    XCTAssertEqual(state.session.remaining(at: start), 900)
    XCTAssertTrue(state.history.isEmpty)
  }

  func testStartAgainCreatesDistinctHistoryEntries() {
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: start)
    let firstID = state.session.id
    state.reconcile(at: start.addingTimeInterval(60))
    state.start(at: start.addingTimeInterval(120))
    XCTAssertNotEqual(state.session.id, firstID)
    state.reconcile(at: start.addingTimeInterval(180))
    XCTAssertEqual(state.history.count, 2)
    XCTAssertEqual(state.history[1].id, firstID)
  }

  func testRepeatedStartDoesNotExtendRunningSession() {
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: start)
    let originalID = state.session.id
    state.start(at: start.addingTimeInterval(30))
    XCTAssertEqual(state.session.id, originalID)
    XCTAssertEqual(state.session.remaining(at: start.addingTimeInterval(30)), 30)
    state.session.setDuration(120)
    XCTAssertEqual(state.session.duration, 60)
  }

  func testDurationValidationAndProgressBounds() {
    XCTAssertEqual(FocusSession(duration: -1).duration, 1)
    XCTAssertEqual(FocusSession(duration: 999_999).duration, 10_800)
    XCTAssertEqual(FocusSession(duration: .nan).duration, 1_500)
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: start)
    XCTAssertEqual(state.session.remaining(at: start.addingTimeInterval(-30)), 60)
    XCTAssertEqual(state.session.progress(at: start.addingTimeInterval(-30)), 0)
    XCTAssertEqual(state.session.remaining(at: start.addingTimeInterval(100)), 0)
    XCTAssertEqual(state.session.progress(at: start.addingTimeInterval(100)), 1)
  }

  func testThoughtCaptureRejectsEmptyTextAndSupportsCompletionAndDeletion() {
    var state = StillState()
    XCTAssertFalse(state.addThought(" \n ", at: start))
    XCTAssertTrue(state.addThought("  Send the invoice \n", at: start))
    let thought = state.thoughts[0]
    XCTAssertEqual(thought.text, "Send the invoice")
    XCTAssertEqual(thought.createdAt, start)
    state.toggleThought(id: thought.id)
    XCTAssertTrue(state.thoughts[0].isDone)
    state.toggleThought(id: thought.id)
    XCTAssertFalse(state.thoughts[0].isDone)
    state.deleteThought(id: thought.id)
    XCTAssertTrue(state.thoughts.isEmpty)
  }

  func testDailyTotalsUseDeadlineInLocalCalendarRatherThanReopenDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
    let lateEvening = calendar.date(
      from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 50))!
    let nextMorning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!
    var state = StillState(session: FocusSession(duration: 300))
    state.start(at: lateEvening)
    state.reconcile(at: nextMorning)
    XCTAssertEqual(state.todayCompletedCount(at: lateEvening, calendar: calendar), 1)
    XCTAssertEqual(state.todayFocusSeconds(at: lateEvening, calendar: calendar), 300)
    XCTAssertEqual(state.todayCompletedCount(at: nextMorning, calendar: calendar), 0)
    XCTAssertEqual(state.todayFocusSeconds(at: nextMorning, calendar: calendar), 0)
  }

  func testChangingDurationAfterCompletionPreparesFreshSession() {
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: start)
    state.reconcile(at: start.addingTimeInterval(60))
    state.session.setDuration(900)
    XCTAssertEqual(state.session.phase, .idle)
    XCTAssertEqual(state.session.remaining(at: start), 900)
    XCTAssertEqual(state.history.count, 1)
  }
}

import Foundation
import StillCore
import XCTest

@testable import Still

@MainActor
final class AppStoreTests: XCTestCase {
  private var folder: URL!
  private var repository: StateRepository!
  private var preferences: UserDefaults!
  private var preferencesName: String!
  private var currentDate: Date!

  override func setUp() async throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    repository = StateRepository(fileURL: folder.appendingPathComponent("state.json"))
    preferencesName = "StillTests.\(UUID().uuidString)"
    preferences = UserDefaults(suiteName: preferencesName)!
    currentDate = Date(timeIntervalSince1970: 1_800_000_000)
  }

  override func tearDown() async throws {
    preferences.removePersistentDomain(forName: preferencesName)
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
  }

  private func makeStore() -> AppStore {
    AppStore(
      repository: repository, defaults: preferences, clock: { [unowned self] in self.currentDate },
      automaticTicking: false)
  }

  func testPauseClickAtDeadlineCompletesWithoutStartingAnotherSession() throws {
    let store = makeStore()
    store.setDuration(1)
    store.primaryAction()
    let originalID = store.state.session.id
    currentDate = currentDate.addingTimeInterval(60)
    store.primaryAction()
    XCTAssertEqual(store.state.session.phase, .finished)
    XCTAssertEqual(store.state.session.id, originalID)
    XCTAssertEqual(store.state.history.count, 1)
    XCTAssertEqual(store.state.history.first?.id, originalID)
    XCTAssertEqual(try repository.load().history.count, 1)
    store.tick(currentDate.addingTimeInterval(1))
    XCTAssertEqual(store.state.history.count, 1)
  }

  func testEndingAtDeadlineStillRecordsCompletedSession() throws {
    let store = makeStore()
    store.setDuration(1)
    store.primaryAction()
    currentDate = currentDate.addingTimeInterval(60)
    store.reset()
    XCTAssertEqual(store.state.session.phase, .idle)
    XCTAssertEqual(store.state.history.count, 1)
    XCTAssertEqual(try repository.load().history.count, 1)
  }

  func testEndingUnfinishedSessionDoesNotRecordFocusTime() {
    let store = makeStore()
    store.setDuration(1)
    store.primaryAction()
    currentDate = currentDate.addingTimeInterval(59)
    store.reset()
    XCTAssertEqual(store.state.session.phase, .idle)
    XCTAssertTrue(store.state.history.isEmpty)
  }

  func testPauseAndResumeUseInjectedClock() {
    let store = makeStore()
    store.setDuration(1)
    store.primaryAction()
    currentDate = currentDate.addingTimeInterval(15)
    store.primaryAction()
    XCTAssertEqual(store.state.session.phase, .paused)
    XCTAssertEqual(store.timeString, "00:45")
    currentDate = currentDate.addingTimeInterval(200)
    store.primaryAction()
    XCTAssertEqual(store.state.session.phase, .running)
    XCTAssertEqual(store.timeString, "00:45")
    currentDate = currentDate.addingTimeInterval(45)
    store.tick(currentDate)
    XCTAssertEqual(store.state.session.phase, .finished)
  }

  func testRelaunchReconcilesElapsedSessionOnce() throws {
    var state = StillState(session: FocusSession(duration: 60))
    state.start(at: currentDate)
    try repository.save(state)
    currentDate = currentDate.addingTimeInterval(100)
    XCTAssertEqual(makeStore().state.history.count, 1)
    XCTAssertEqual(makeStore().state.history.count, 1)
  }

  func testCorruptFileRemainsUntouchedAfterEditingFallbackState() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let original = Data("{not valid JSON".utf8)
    try original.write(to: repository.fileURL)
    let store = makeStore()
    XCTAssertNotNil(store.storageError)
    store.addThought("Keep this visible for this session")
    store.setIntention("A fresh intention")
    store.primaryAction()
    XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    XCTAssertNotNil(store.storageError)
    XCTAssertEqual(store.state.thoughts.count, 1)
  }

  func testLongThoughtIsPreservedAndSuccessfulCaptureClearsSharedDraft() throws {
    let store = makeStore()
    let thought = String(repeating: "A complete thought. ", count: 200)
    store.thoughtDraft = thought
    store.captureThought()
    XCTAssertEqual(store.state.thoughts.first?.text, thought.trimmingCharacters(in: .whitespaces))
    XCTAssertEqual(try repository.load().thoughts.first?.text, store.state.thoughts.first?.text)
    XCTAssertEqual(store.thoughtDraft, "")
  }

  func testBlankThoughtDoesNotClearUnacceptedDraftOrCreateRecord() {
    let store = makeStore()
    store.thoughtDraft = " \n "
    store.captureThought()
    XCTAssertTrue(store.state.thoughts.isEmpty)
    XCTAssertEqual(store.thoughtDraft, " \n ")
  }

  func testIntentionDoesNotSilentlyTruncatePastedText() {
    let store = makeStore()
    let intention = String(repeating: "Plan ", count: 100)
    store.setIntention(intention)
    XCTAssertEqual(store.state.session.intention, intention)
  }

  func testAudioPreferencesRestoreWithoutStartingPlayback() {
    let store = makeStore()
    store.audio.volume = 0.72
    store.audio.soundscape = .shore
    let restored = makeStore()
    XCTAssertEqual(restored.audio.volume, 0.72, accuracy: 0.001)
    XCTAssertEqual(restored.audio.soundscape, .shore)
    XCTAssertFalse(restored.audio.isPlaying)
    XCTAssertNil(restored.audio.errorMessage)
  }

  func testInvalidAudioPreferencesUseSafeDefaults() {
    preferences.set(4.0, forKey: "audio.volume")
    preferences.set("missing-scene", forKey: "audio.soundscape")
    let store = makeStore()
    XCTAssertEqual(store.audio.volume, 1)
    XCTAssertEqual(store.audio.soundscape, .rain)
    XCTAssertFalse(store.audio.isPlaying)
  }

  func testTaskPreparationAndUpdatesPersist() throws {
    let store = makeStore()
    let projectID = try XCTUnwrap(store.addProject("Still"))
    let taskID = try XCTUnwrap(
      store.createTask(title: "Polish the workspace", projectID: projectID, estimateMinutes: 45))
    store.prepareTask(taskID)
    XCTAssertEqual(store.selectedTask?.id, taskID)
    XCTAssertEqual(store.state.session.duration, 45 * 60)
    var task = try XCTUnwrap(store.selectedTask)
    task.notes = "Check keyboard navigation."
    store.updateTask(task)
    store.renameProject(projectID, name: "Still for Mac")
    let restored = makeStore()
    XCTAssertEqual(restored.selectedTask?.notes, task.notes)
    XCTAssertEqual(restored.state.projects.first?.name, "Still for Mac")
  }

  func testDeletingAndUndoingTaskPreservesOrderAndUnrelatedEdits() throws {
    let store = makeStore()
    let firstID = try XCTUnwrap(store.createTask(title: "First"))
    let secondID = try XCTUnwrap(store.createTask(title: "Second"))
    let originalOrder = store.state.tasks.map(\.id)
    store.deleteTask(firstID)
    XCTAssertEqual(store.recentlyDeletedTask?.id, firstID)
    store.queueTask(secondID, queued: false)
    store.addThought("Keep this separate change")
    store.undoDeleteTask()
    XCTAssertEqual(store.state.tasks.map(\.id), originalOrder)
    XCTAssertEqual(store.state.tasks.first { $0.id == secondID }?.isQueued, false)
    XCTAssertEqual(store.state.thoughts.count, 1)
    XCTAssertNil(store.recentlyDeletedTask)
    XCTAssertEqual(try repository.load().tasks.map(\.id), originalOrder)
  }

  func testUndoTaskDeletionAfterDeletingProjectDoesNotRestoreDanglingProject() throws {
    let store = makeStore()
    let projectID = try XCTUnwrap(store.addProject("Temporary"))
    let taskID = try XCTUnwrap(store.createTask(title: "Task", projectID: projectID))
    store.deleteTask(taskID)
    store.deleteProject(projectID)
    store.undoDeleteTask()
    XCTAssertNil(store.state.tasks.first?.projectID)
    XCTAssertEqual(try repository.load().tasks.count, 1)
  }

  func testActiveSessionCannotBeReplacedByAnotherTask() throws {
    let store = makeStore()
    let first = try XCTUnwrap(store.createTask(title: "Current task"))
    let second = try XCTUnwrap(store.createTask(title: "Next task"))
    XCTAssertTrue(store.prepareTask(first))
    store.primaryAction()
    XCTAssertFalse(store.prepareTask(second))
    XCTAssertEqual(store.selectedTask?.id, first)
    XCTAssertEqual(store.state.session.phase, .running)
  }

  func testEditingSelectedIdleTaskUpdatesSessionTitleAndDuration() throws {
    let store = makeStore()
    let id = try XCTUnwrap(store.createTask(title: "Draft", estimateMinutes: 25))
    XCTAssertTrue(store.prepareTask(id))
    var task = try XCTUnwrap(store.selectedTask)
    task.title = "Review the draft"
    task.estimateMinutes = 45
    store.updateTask(task)
    XCTAssertEqual(store.state.session.intention, "Review the draft")
    XCTAssertEqual(store.state.session.duration, 45 * 60)
    XCTAssertEqual(store.state.session.phase, .idle)
    XCTAssertEqual(try repository.load().session.intention, "Review the draft")
  }

  func testEditingSelectedActiveTaskPreservesSessionSnapshot() throws {
    let store = makeStore()
    let id = try XCTUnwrap(store.createTask(title: "Draft", estimateMinutes: 25))
    store.prepareTask(id)
    store.primaryAction()
    let session = store.state.session
    var task = try XCTUnwrap(store.selectedTask)
    task.title = "Review the draft"
    task.estimateMinutes = 45
    store.updateTask(task)
    XCTAssertEqual(store.state.session, session)
    XCTAssertEqual(store.selectedTask?.title, "Review the draft")
    XCTAssertEqual(try repository.load().session, session)
  }

  func testPreparingMissingTaskReturnsFalseAndKeepsSelection() throws {
    let store = makeStore()
    let id = try XCTUnwrap(store.createTask(title: "Existing task"))
    XCTAssertTrue(store.prepareTask(id))
    XCTAssertFalse(store.prepareTask(UUID()))
    XCTAssertEqual(store.selectedTask?.id, id)
  }
  func testImportedTasksPreserveExistingWorkAndCompletedState() throws {
    let store = makeStore()
    let original = try XCTUnwrap(store.createTask(title: "Existing work"))
    store.prepareTask(original)
    store.primaryAction()
    let active = store.state.session
    let project = try XCTUnwrap(store.addProject("Imported"))
    let items = try TaskImport.parse("- [ ] Review UI\n- [x] Fix tests")
    store.importTasks(items, projectID: project, queued: false)
    XCTAssertEqual(store.state.tasks.map(\.title), ["Existing work", "Review UI", "Fix tests"])
    XCTAssertEqual(store.state.session, active)
    XCTAssertFalse(store.state.tasks[1].isQueued)
    XCTAssertEqual(store.state.tasks[1].projectID, project)
    XCTAssertTrue(store.state.tasks[2].isComplete)
    XCTAssertEqual(try repository.load(), store.state)
  }

  func testURLHandoffCreatesContextWithoutInterruptingCurrentSession() throws {
    let store = makeStore()
    store.setIntention("Already focusing")
    store.primaryAction()
    let session = store.state.session
    let url = try XCTUnwrap(
      URL(
        string:
          "still://task?title=Review%20PR&notes=Check%20tests&project=Website&minutes=15&url=https%3A%2F%2Fexample.com"
      ))
    store.handleURL(url)
    XCTAssertEqual(store.state.tasks.count, 1)
    XCTAssertEqual(store.state.tasks[0].title, "Review PR")
    XCTAssertEqual(store.state.tasks[0].notes, "Check tests")
    XCTAssertEqual(store.state.tasks[0].estimateMinutes, 15)
    XCTAssertEqual(store.state.tasks[0].links[0].url, "https://example.com")
    XCTAssertEqual(store.state.projects.count, 1)
    XCTAssertEqual(store.state.session, session)
    XCTAssertFalse(store.audio.isPlaying)
    XCTAssertEqual(try repository.load(), store.state)
    store.handleURL(try XCTUnwrap(URL(string: "still://task?title=Another&project=website")))
    XCTAssertEqual(store.state.projects.count, 1)
  }

  func testInvalidHandoffDoesNotMutateWorkspace() throws {
    let store = makeStore()
    let before = store.state
    store.handleURL(try XCTUnwrap(URL(string: "still://task?title=Unsafe&url=file:///tmp/example")))
    XCTAssertNotNil(store.handoffError)
    XCTAssertEqual(store.state, before)
    store.handleURL(try XCTUnwrap(URL(string: "still://note?text=Remember%20this")))
    XCTAssertNil(store.handoffError)
    XCTAssertEqual(store.state.thoughts.first?.text, "Remember this")
  }

}

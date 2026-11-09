import Foundation
import XCTest

@testable import StillCore

final class WorkspaceTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testTaskCreationTrimsTitlesAndBoundsEstimates() throws {
    var state = StillState()
    XCTAssertNil(state.addTask(title: "  \n "))
    XCTAssertNil(state.addTask(title: "Unassigned", projectID: UUID()))
    let id = try XCTUnwrap(
      state.addTask(title: "  Design the editor \n", estimateMinutes: 300, at: now))
    let task = try XCTUnwrap(state.tasks.first)
    XCTAssertEqual(task.id, id)
    XCTAssertEqual(task.title, "Design the editor")
    XCTAssertEqual(task.estimateMinutes, 180)
    XCTAssertEqual(task.createdAt, now)
    XCTAssertTrue(task.isQueued)
    XCTAssertFalse(task.isComplete)
  }

  func testTaskUpdatesPreservePositionAndRejectInvalidValues() throws {
    var state = StillState()
    let first = try XCTUnwrap(state.addTask(title: "First"))
    let second = try XCTUnwrap(state.addTask(title: "Second"))
    var task = state.tasks[0]
    task.title = "  Improved  "
    task.notes = "Remember the keyboard shortcuts."
    task.links = [TaskLink(title: "Reference", url: "https://example.com")]
    task.estimateMinutes = -5
    XCTAssertTrue(state.updateTask(task))
    XCTAssertEqual(state.tasks.map(\.id), [first, second])
    XCTAssertEqual(state.tasks[0].title, "Improved")
    XCTAssertEqual(state.tasks[0].estimateMinutes, 1)
    task.title = " "
    XCTAssertFalse(state.updateTask(task))
    XCTAssertEqual(state.tasks[0].title, "Improved")
    task.title = "Valid"
    task.projectID = UUID()
    XCTAssertFalse(state.updateTask(task))
  }

  func testTaskCompletionAndQueueMembershipAreIndependent() throws {
    var state = StillState()
    let id = try XCTUnwrap(state.addTask(title: "Work", at: now))
    state.queueTask(id: id, queued: false)
    XCTAssertTrue(state.queuedTasks.isEmpty)
    XCTAssertEqual(state.unfinishedTasks.count, 1)
    state.queueTask(id: id, queued: true)
    state.toggleTaskComplete(id: id, at: now.addingTimeInterval(60))
    XCTAssertTrue(state.queuedTasks.isEmpty)
    XCTAssertTrue(state.unfinishedTasks.isEmpty)
    XCTAssertEqual(state.tasks[0].completedAt, now.addingTimeInterval(60))
    state.toggleTaskComplete(id: id)
    XCTAssertEqual(state.queuedTasks.map(\.id), [id])
  }

  func testTaskOrderMovesBeforeAndToEndWithoutDisturbingOtherTasks() throws {
    var state = StillState()
    let first = try XCTUnwrap(state.addTask(title: "One"))
    let second = try XCTUnwrap(state.addTask(title: "Two"))
    let third = try XCTUnwrap(state.addTask(title: "Three"))
    state.moveTask(id: third, before: first)
    XCTAssertEqual(state.tasks.map(\.id), [third, first, second])
    state.moveTask(id: third, before: nil)
    XCTAssertEqual(state.tasks.map(\.id), [first, second, third])
    state.moveTask(id: first, before: first)
    state.moveTask(id: first, before: UUID())
    state.moveTask(id: UUID(), before: first)
    XCTAssertEqual(state.tasks.map(\.id), [first, second, third])
    state.moveTask(id: first, before: third)
    XCTAssertEqual(state.tasks.map(\.id), [second, first, third])
  }

  func testProjectLifecycleKeepsTasksWhenProjectDeleted() throws {
    var state = StillState()
    XCTAssertNil(state.addProject(name: " \n"))
    let project = try XCTUnwrap(state.addProject(name: "  Still  ", at: now))
    XCTAssertNil(state.addProject(name: "still"))
    XCTAssertEqual(state.projects[0].createdAt, now)
    let task = try XCTUnwrap(state.addTask(title: "Ship", projectID: project))
    XCTAssertTrue(state.renameProject(id: project, name: "Studio"))
    XCTAssertEqual(state.projects[0].name, "Studio")
    XCTAssertFalse(state.renameProject(id: project, name: " "))
    state.deleteProject(id: project)
    XCTAssertTrue(state.projects.isEmpty)
    XCTAssertEqual(state.tasks.map(\.id), [task])
    XCTAssertNil(state.tasks[0].projectID)
  }

  func testPrepareTaskStartsLinkedSessionAndCompletionKeepsTaskOpen() throws {
    var state = StillState()
    let project = try XCTUnwrap(state.addProject(name: "Still"))
    let task = try XCTUnwrap(
      state.addTask(title: "Refine typography", projectID: project, estimateMinutes: 15))
    XCTAssertTrue(state.prepareTask(id: task))
    XCTAssertEqual(state.session.phase, .idle)
    XCTAssertEqual(state.session.intention, "Refine typography")
    XCTAssertEqual(state.session.duration, 900)
    XCTAssertEqual(state.session.taskID, task)
    XCTAssertEqual(state.session.projectID, project)
    state.start(at: now)
    state.reconcile(at: now.addingTimeInterval(900))
    XCTAssertEqual(state.history.first?.taskID, task)
    XCTAssertEqual(state.history.first?.projectID, project)
    XCTAssertFalse(state.tasks[0].isComplete)
    XCTAssertTrue(state.prepareTask(id: task))
    state.start(at: now.addingTimeInterval(1_000))
    state.reconcile(at: now.addingTimeInterval(1_900))
    XCTAssertEqual(state.history.filter { $0.taskID == task }.count, 2)
  }

  func testPrepareTaskCannotReplaceRunningOrPausedWorkOrSelectCompletedTask() throws {
    var state = StillState()
    let first = try XCTUnwrap(state.addTask(title: "One"))
    let second = try XCTUnwrap(state.addTask(title: "Two"))
    state.prepareTask(id: first)
    state.start(at: now)
    XCTAssertFalse(state.prepareTask(id: second))
    state.pause(at: now.addingTimeInterval(1))
    XCTAssertFalse(state.prepareTask(id: second))
    XCTAssertEqual(state.session.taskID, first)
    state.reset()
    XCTAssertEqual(state.session.taskID, first)
    state.toggleTaskComplete(id: second)
    XCTAssertFalse(state.prepareTask(id: second))
    XCTAssertFalse(state.prepareTask(id: UUID()))
  }

  func testDeletingTaskAndProjectPreservesRunningAndHistoricalAssociations() throws {
    var state = StillState()
    let project = try XCTUnwrap(state.addProject(name: "Still"))
    let task = try XCTUnwrap(state.addTask(title: "Work", projectID: project, estimateMinutes: 1))
    state.prepareTask(id: task)
    state.start(at: now)
    state.deleteTask(id: task)
    state.deleteProject(id: project)
    XCTAssertEqual(state.session.taskID, task)
    XCTAssertEqual(state.session.projectID, project)
    state.reconcile(at: now.addingTimeInterval(60))
    XCTAssertEqual(state.history[0].taskID, task)
    XCTAssertEqual(state.history[0].projectID, project)
    XCTAssertTrue(state.isValidWorkspace)
  }

  func testWorkspaceRoundTripRetainsNotesLinksQueueAndSelection() throws {
    var state = StillState()
    let project = try XCTUnwrap(state.addProject(name: "Still", at: now))
    let task = try XCTUnwrap(state.addTask(title: "Work", projectID: project, at: now))
    var item = state.tasks[0]
    item.notes = "A meaningful description.\nA second line."
    item.links = [TaskLink(title: "Spec", url: "https://example.com/spec")]
    state.updateTask(item)
    state.queueTask(id: task, queued: false)
    state.prepareTask(id: task)
    state.start(at: now)
    let restored = try JSONDecoder().decode(StillState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(restored, state)
    XCTAssertEqual(restored.session.remaining(at: now.addingTimeInterval(60)), 1_440)
  }

  func testLegacyStateWithoutWorkspaceOrSessionLinksStillDecodes() throws {
    var state = StillState(session: FocusSession(intention: "Legacy", duration: 60))
    state.start(at: now)
    state.reconcile(at: now.addingTimeInterval(60))
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    json.removeValue(forKey: "tasks")
    json.removeValue(forKey: "projects")
    var session = try XCTUnwrap(json["session"] as? [String: Any])
    session.removeValue(forKey: "taskID")
    session.removeValue(forKey: "projectID")
    json["session"] = session
    let restored = try JSONDecoder().decode(
      StillState.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(restored, state)
    XCTAssertTrue(restored.tasks.isEmpty)
    XCTAssertTrue(restored.projects.isEmpty)
    XCTAssertNil(restored.session.taskID)
    XCTAssertNil(restored.history[0].taskID)
  }

  func testWorkspaceValidationRejectsDuplicateIDsAndDanglingProject() {
    let project = Project(name: "Still")
    let task = TaskItem(title: "Work")
    XCTAssertFalse(StillState(tasks: [task, task]).isValidWorkspace)
    XCTAssertFalse(StillState(projects: [project, project]).isValidWorkspace)
    XCTAssertFalse(StillState(tasks: [TaskItem(title: "Work", projectID: UUID())]).isValidWorkspace)
    var invalid = task
    invalid.estimateMinutes = 0
    XCTAssertFalse(StillState(tasks: [invalid]).isValidWorkspace)
    XCTAssertFalse(StillState(tasks: [TaskItem(title: " ")]).isValidWorkspace)
    let link = TaskLink(url: "https://example.com")
    XCTAssertFalse(
      StillState(tasks: [TaskItem(title: "Work", links: [link, link])]).isValidWorkspace)
  }
}

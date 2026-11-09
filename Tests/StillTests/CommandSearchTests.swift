import Foundation
import StillCore
import XCTest

@testable import Still

final class CommandSearchTests: XCTestCase {
  func testInitialResultsPreferQueuedTasksAndIncludeProjects() {
    let project = Project(name: "Website")
    let backlog = TaskItem(title: "Backlog", isQueued: false)
    let queued = TaskItem(title: "Queued")
    let completed = TaskItem(title: "Done", completedAt: Date())
    let results = commandSearch(
      query: " \n ", tasks: [backlog, completed, queued], projects: [project])
    XCTAssertEqual(results.map(\.title), ["Queued", "Backlog", "Website"])
  }

  func testSearchMatchesNotesAndProjectNamesAcrossWords() {
    let project = Project(name: "Website")
    let task = TaskItem(title: "Review", notes: "Keyboard navigation", projectID: project.id)
    let results = commandSearch(query: "website keyboard", tasks: [task], projects: [project])
    XCTAssertEqual(results, [.task(task, projectName: "Website")])
  }

  func testSearchIgnoresCaseAccentsAndOuterWhitespace() {
    let task = TaskItem(title: "Café launch")
    XCTAssertEqual(
      commandSearch(query: " CAFE ", tasks: [task], projects: []).map(\.title), ["Café launch"])
  }

  func testTitleMatchRanksBeforeNotesAndCompletedTasksRemainSearchable() {
    let notes = TaskItem(title: "Other task", notes: "Launch")
    let done = TaskItem(title: "Launch", completedAt: Date())
    let exact = TaskItem(title: "Launch")
    let prefix = TaskItem(title: "Launch checklist")
    let results = commandSearch(query: "Launch", tasks: [notes, done, prefix, exact], projects: [])
    XCTAssertEqual(
      results,
      [
        .task(exact, projectName: nil), .task(prefix, projectName: nil),
        .task(notes, projectName: nil), .task(done, projectName: nil),
      ])
    XCTAssertEqual(results.last?.subtitle, "Completed · No project")
  }

  func testProjectExactMatchRanksAheadOfTaskProjectMatches() {
    let project = Project(name: "Website")
    let task = TaskItem(title: "Review the homepage", projectID: project.id)
    let results = commandSearch(query: "website", tasks: [task], projects: [project])
    XCTAssertEqual(results.first, .project(project))
    XCTAssertEqual(results.last, .task(task, projectName: "Website"))
  }

  func testResultLimitAndNoMatch() {
    let tasks = (1...30).map { TaskItem(title: "Task \($0)") }
    XCTAssertEqual(commandSearch(query: "task", tasks: tasks, projects: []).count, 12)
    XCTAssertEqual(commandSearch(query: "task", tasks: tasks, projects: [], limit: 2).count, 2)
    XCTAssertTrue(commandSearch(query: "missing", tasks: tasks, projects: []).isEmpty)
    XCTAssertTrue(commandSearch(query: "", tasks: tasks, projects: [], limit: 0).isEmpty)
    XCTAssertTrue(commandSearch(query: "", tasks: tasks, projects: [], limit: -1).isEmpty)
  }

  func testInitialResultsReserveSpaceForProjectsWithinLimit() {
    let tasks = (1...30).map { TaskItem(title: "Task \($0)") }
    let projects = (1...5).map { Project(name: "Project \($0)") }
    let results = commandSearch(query: "", tasks: tasks, projects: projects)
    XCTAssertEqual(results.count, 12)
    XCTAssertEqual(results.suffix(3).map(\.title), ["Project 1", "Project 2", "Project 3"])
  }

  func testTaskAndProjectWithSameUUIDHaveDifferentResultIdentities() {
    let id = UUID()
    let task = TaskItem(id: id, title: "Task")
    let project = Project(id: id, name: "Project")
    let results = commandSearch(query: "", tasks: [task], projects: [project])
    XCTAssertEqual(Set(results.map(\.id)).count, 2)
  }
}

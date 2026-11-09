import StillCore
import XCTest

@testable import Still

final class WorkExportTests: XCTestCase {
  func testChecklistRoundTripsTaskTitlesAndCompletion() throws {
    let tasks = [
      TaskItem(title: "Review café layout"),
      TaskItem(title: "Fix quotes & links", completedAt: .now),
    ]
    let parsed = try TaskImport.parse(WorkExport.checklist(tasks: tasks))
    XCTAssertEqual(parsed.map(\.title), tasks.map(\.title))
    XCTAssertEqual(parsed.map(\.isComplete), [false, true])
  }
  func testBriefPreservesNotesAndReferencesWithoutInventingContext() {
    let task = TaskItem(
      title: "Review", notes: "Check A\nThen B", estimateMinutes: 45,
      links: [TaskLink(title: "Spec", url: "https://example.com/a?b=1&c=2")])
    let brief = WorkExport.brief(task: task, project: Project(name: "Website"))
    XCTAssertTrue(brief.contains("Project: Website"))
    XCTAssertTrue(brief.contains("45 minutes"))
    XCTAssertTrue(brief.contains("Check A\nThen B"))
    XCTAssertTrue(brief.contains("https://example.com/a?b=1&c=2"))
    let empty = WorkExport.brief(task: TaskItem(title: "Simple"), project: nil)
    XCTAssertFalse(empty.contains("## Notes"))
    XCTAssertFalse(empty.contains("## References"))
  }
}

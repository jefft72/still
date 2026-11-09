import XCTest

@testable import StillCore

final class TaskImportTests: XCTestCase {
  func testPlaintextLinesPreserveUnicodeAndDuplicates() throws {
    let tasks = try TaskImport.parse(
      "  Sketch the editor  \n\n修正タイポグラフィ\nPlan café visit ☕️\nSketch the editor")
    XCTAssertEqual(
      tasks,
      [
        ImportedTask(title: "Sketch the editor"),
        ImportedTask(title: "修正タイポグラフィ"),
        ImportedTask(title: "Plan café visit ☕️"),
        ImportedTask(title: "Sketch the editor"),
      ])
  }

  func testMarkdownListsExcludeHeadingsAndSurroundingProse() throws {
    let text = """
      # Today's plan
      Here is a plan for the afternoon.
      - [ ] Draft the settings screen
      - [x] Fix keyboard navigation
      * [X] Review the release notes
      + Publish the build
      1. Write a concise description
      2) Send the update
      This is an explanation, not a task.
      """
    XCTAssertEqual(
      try TaskImport.parse(text),
      [
        ImportedTask(title: "Draft the settings screen"),
        ImportedTask(title: "Fix keyboard navigation", isComplete: true),
        ImportedTask(title: "Review the release notes", isComplete: true),
        ImportedTask(title: "Publish the build"),
        ImportedTask(title: "Write a concise description"),
        ImportedTask(title: "Send the update"),
      ])
  }

  func testOrderedCheckboxesAndNestedItemsAreFlattenedInOrder() throws {
    let text = "1. [ ] Parent\n   - [x] Child\n\t2) [X] Another child\n3. [ ] Last"
    XCTAssertEqual(
      try TaskImport.parse(text),
      [
        ImportedTask(title: "Parent"),
        ImportedTask(title: "Child", isComplete: true),
        ImportedTask(title: "Another child", isComplete: true),
        ImportedTask(title: "Last"),
      ])
  }

  func testFencedCodeAndItsListMarkersAreIgnored() throws {
    let text = """
      ```markdown
      - [x] Not a task
      # Not a heading
      ```
      Actual plaintext task
      ~~~~text
      - Another example
      ~~~
      Still inside the four-character fence
      ~~~~
      Second plaintext task
      """
    XCTAssertEqual(
      try TaskImport.parse(text),
      [
        ImportedTask(title: "Actual plaintext task"), ImportedTask(title: "Second plaintext task"),
      ])
  }

  func testUnclosedFenceAndFalseClosingFenceDoNotLeakCodeIntoTasks() throws {
    let text = "- Keep this\n```\n- Do not import\n```not a closing fence\n- Also code"
    XCTAssertEqual(try TaskImport.parse(text), [ImportedTask(title: "Keep this")])
  }

  func testMalformedCheckboxesRemainLiteralText() throws {
    let text = "- [yes] Decide\n- [x]No space\n- [ ]\n- [] Empty brackets\n- [X Decide"
    XCTAssertEqual(
      try TaskImport.parse(text),
      [
        ImportedTask(title: "[yes] Decide"), ImportedTask(title: "[x]No space"),
        ImportedTask(title: "[] Empty brackets"), ImportedTask(title: "[X Decide"),
      ])
  }

  func testUnsafeLookingContentIsPreservedAsTextWithoutInterpretation() throws {
    let title = #"<script>alert('hello')</script> $(rm -rf example) [link](javascript:alert(1))"#
    XCTAssertEqual(try TaskImport.parse("- \(title)"), [ImportedTask(title: title)])
  }

  func testCRLFAndHashtagsAreHandledWithoutLosingText() throws {
    let text = "# Heading\r\n\r\nFirst task\r\n#launch\r\nSecond task\r\n"
    XCTAssertEqual(
      try TaskImport.parse(text),
      [
        ImportedTask(title: "First task"), ImportedTask(title: "#launch"),
        ImportedTask(title: "Second task"),
      ])
  }

  func testEmptyInputAndEmptyListItemsProduceNoTasks() throws {
    XCTAssertEqual(try TaskImport.parse(" \n\t\r\n# Heading"), [])
    XCTAssertEqual(try TaskImport.parse("Introduction\n-\n*\n1.\n2)\n+ [ ]\nExplanation"), [])
  }

  func testPunctuationWithoutListWhitespaceRemainsPlaintext() throws {
    XCTAssertEqual(
      try TaskImport.parse("-dash\n*asterisk\n1.5 hours\n2)Parenthesis"),
      [
        ImportedTask(title: "-dash"), ImportedTask(title: "*asterisk"),
        ImportedTask(title: "1.5 hours"), ImportedTask(title: "2)Parenthesis"),
      ])
  }

  func testTaskLimitThrowsRatherThanTruncating() throws {
    let allowed = Array(repeating: "- Task", count: TaskImport.maximumTasks).joined(separator: "\n")
    XCTAssertEqual(try TaskImport.parse(allowed).count, TaskImport.maximumTasks)
    XCTAssertThrowsError(try TaskImport.parse(allowed + "\n- One more")) { error in
      XCTAssertEqual(error as? TaskImport.ImportError, .tooManyTasks)
    }
    let plaintext = Array(repeating: "Task", count: TaskImport.maximumTasks + 1).joined(
      separator: "\n")
    XCTAssertThrowsError(try TaskImport.parse(plaintext)) { error in
      XCTAssertEqual(error as? TaskImport.ImportError, .tooManyTasks)
    }
  }

  func testLargeProseBeforeAListDoesNotCountAgainstTaskLimit() throws {
    let prose = Array(repeating: "Some explanatory prose.", count: 600).joined(separator: "\n")
    XCTAssertEqual(
      try TaskImport.parse(prose + "\n- The actual task"), [ImportedTask(title: "The actual task")])
  }

  func testCharacterLimitAndLongTitlesNeverSilentlyTruncate() throws {
    let allowed = String(repeating: "a", count: TaskImport.maximumCharacters)
    XCTAssertEqual(try TaskImport.parse(allowed), [ImportedTask(title: allowed)])
    XCTAssertThrowsError(try TaskImport.parse(allowed + "a")) { error in
      XCTAssertEqual(error as? TaskImport.ImportError, .tooLarge)
    }
  }
}

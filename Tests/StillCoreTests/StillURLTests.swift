import Foundation
import XCTest

@testable import StillCore

final class StillURLTests: XCTestCase {
  private func link(_ action: String, _ values: [URLQueryItem]) throws -> URL {
    var components = URLComponents()
    components.scheme = "still"
    components.host = action
    components.queryItems = values
    return try XCTUnwrap(components.url)
  }

  func testTaskHandoffPreservesEncodedUnicodeAndDelimiters() throws {
    let title = "Café & design #2 / 日本語"
    let notes = "First line\nKeep a=b & c+d #details exactly.\n"
    let reference = try XCTUnwrap(
      URL(string: "https://example.com/review?branch=main&tab=files#L25"))
    let url = try link(
      "task",
      [
        URLQueryItem(name: "title", value: title),
        URLQueryItem(name: "notes", value: notes),
        URLQueryItem(name: "project", value: "  Product design  "),
        URLQueryItem(name: "minutes", value: "45"),
        URLQueryItem(name: "url", value: reference.absoluteString),
      ])
    XCTAssertEqual(
      try StillURLAction.parse(url),
      .task(
        title: title, notes: notes, project: "Product design", minutes: 45, reference: reference))
  }

  func testTaskDefaultsAndUnknownParameters() throws {
    let url = try link(
      "task",
      [
        URLQueryItem(name: "title", value: "  Review the changes  "),
        URLQueryItem(name: "future-client-version", value: "3"),
        URLQueryItem(name: "project", value: " \n "),
      ])
    XCTAssertEqual(
      try StillURLAction.parse(url),
      .task(title: "Review the changes", notes: "", project: nil, minutes: 25, reference: nil))
  }

  func testNoteHandoffDecodesTextWithoutFormStylePlusReplacement() throws {
    let url = try link("note", [URLQueryItem(name: "text", value: "  C++ & Swift #notes ☕  ")])
    XCTAssertEqual(try StillURLAction.parse(url), .note("C++ & Swift #notes ☕"))
  }

  func testMissingAndWhitespaceOnlyRequiredValuesAreRejected() throws {
    for (action, parameter) in [("task", "title"), ("note", "text")] {
      for values in [
        [], [URLQueryItem(name: parameter, value: nil)],
        [URLQueryItem(name: parameter, value: " \n ")],
      ] {
        let url = try link(action, values)
        XCTAssertThrowsError(try StillURLAction.parse(url)) {
          XCTAssertEqual($0 as? StillURLError, .missingValue(parameter))
        }
      }
    }
  }

  func testInvalidDurationsAreRejectedWithoutClamping() throws {
    for value in [
      "0", "181", "-1", "25.5", "abc", "", " 25 ", "+25", "٢٥", String(repeating: "9", count: 100),
    ] {
      let url = try link(
        "task",
        [
          URLQueryItem(name: "title", value: "Task"), URLQueryItem(name: "minutes", value: value),
        ])
      XCTAssertThrowsError(try StillURLAction.parse(url)) {
        XCTAssertEqual($0 as? StillURLError, .invalidMinutes)
      }
    }
  }

  func testDurationBoundariesAreAccepted() throws {
    for minutes in [1, 180] {
      let url = try link(
        "task",
        [
          URLQueryItem(name: "title", value: "Task"),
          URLQueryItem(name: "minutes", value: String(minutes)),
        ])
      XCTAssertEqual(
        try StillURLAction.parse(url),
        .task(title: "Task", notes: "", project: nil, minutes: minutes, reference: nil))
    }
  }

  func testDuplicateParametersAreRejectedIncludingUnknownNames() throws {
    for name in ["title", "minutes", "future"] {
      let url = try link(
        "task",
        [
          URLQueryItem(name: "title", value: "Task"), URLQueryItem(name: name, value: "one"),
          URLQueryItem(name: name, value: "two"),
        ])
      XCTAssertThrowsError(try StillURLAction.parse(url)) {
        XCTAssertEqual($0 as? StillURLError, .duplicateParameter(name))
      }
    }
  }

  func testExecutableAndLocalReferencesAreRejected() throws {
    for reference in [
      "javascript:alert(1)", "file:///etc/passwd", "data:text/plain,hello",
      "still://note?text=loop",
      "x-apple.systempreferences:com.apple.preference.security", "https:relative-path",
      "//example.com",
      "https://user:password@example.com", "https://@example.com", "",
    ] {
      let url = try link(
        "task",
        [
          URLQueryItem(name: "title", value: "Task"), URLQueryItem(name: "url", value: reference),
        ])
      XCTAssertThrowsError(try StillURLAction.parse(url), reference) {
        XCTAssertEqual($0 as? StillURLError, .unsafeReference)
      }
    }
  }

  func testHTTPReferenceIsAcceptedAsData() throws {
    let reference = try XCTUnwrap(URL(string: "http://localhost:3000/review"))
    let url = try link(
      "task",
      [
        URLQueryItem(name: "title", value: "Review"),
        URLQueryItem(name: "url", value: reference.absoluteString),
      ])
    XCTAssertEqual(
      try StillURLAction.parse(url),
      .task(title: "Review", notes: "", project: nil, minutes: 25, reference: reference))
  }

  func testUnexpectedSchemeActionAuthorityPathAndFragmentAreRejected() throws {
    let cases: [(String, StillURLError)] = [
      ("https://task?title=Example", .invalidScheme),
      ("still://execute?title=Example", .unknownAction),
      ("still:task?title=Example", .unexpectedPath),
      ("still://name@task?title=Example", .unexpectedAuthority),
      ("still://name:secret@task?title=Example", .unexpectedAuthority),
      ("still://task:80?title=Example", .unexpectedAuthority),
      ("still://task/run?title=Example", .unexpectedPath),
      ("still://task?title=Example#missing-text", .unexpectedFragment),
    ]
    for (text, error) in cases {
      let url = try XCTUnwrap(URL(string: text))
      XCTAssertThrowsError(try StillURLAction.parse(url), text) {
        XCTAssertEqual($0 as? StillURLError, error)
      }
    }
  }

  func testSchemeAndActionAreCaseInsensitiveAndTrailingSlashIsAccepted() throws {
    let url = try XCTUnwrap(URL(string: "STILL://NOTE/?text=Remember"))
    XCTAssertEqual(try StillURLAction.parse(url), .note("Remember"))
  }

  func testLongContentIsPreservedWithinLimitAndOversizedLinksFail() throws {
    let text = String(repeating: "a", count: 10_000)
    XCTAssertEqual(
      try StillURLAction.parse(link("note", [URLQueryItem(name: "text", value: text)])), .note(text)
    )
    let oversized = try link(
      "note", [URLQueryItem(name: "text", value: String(repeating: "a", count: 200_000))])
    XCTAssertThrowsError(try StillURLAction.parse(oversized)) {
      XCTAssertEqual($0 as? StillURLError, .tooLong)
    }
  }
}

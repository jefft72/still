import Foundation
import StillCore
import XCTest

@testable import Still

final class HistoryExportTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_800_000_000)

  func testQuotesCommasQuotesNewlinesAndUnicode() {
    let record = record(title: "Review \"café\", then\nship")
    let csv = HistoryExport.csv(records: [record], projects: [])
    XCTAssertTrue(csv.hasPrefix("intention,started_at,completed_at,duration_minutes,project\r\n"))
    XCTAssertTrue(csv.contains("\"Review \"\"café\"\", then\nship\""))
    XCTAssertTrue(csv.hasSuffix(",\"25\",\"\"\r\n"))
  }

  func testNeutralizesSpreadsheetFormulasIncludingLeadingWhitespace() {
    for title in ["=SUM(1,2)", "+42", "-42", "@SUM(A1)", " \t=1+1", "\ttext", "\n=1+1"] {
      let csv = HistoryExport.csv(records: [record(title: title)], projects: [])
      XCTAssertTrue(csv.contains("\"'\(title)\""), "Unsafe export for \(title.debugDescription)")
    }
  }

  func testProjectNamesReceiveTheSameFormulaProtection() {
    let project = Project(name: "=HYPERLINK(\"file:///tmp/test\")")
    let csv = HistoryExport.csv(records: [record(projectID: project.id)], projects: [project])
    XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"file:///tmp/test\"\")\""))
  }

  func testDatesAreUTCAndMinutesUseLocaleIndependentDecimals() {
    let csv = HistoryExport.csv(records: [record(duration: 90)], projects: [])
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    XCTAssertTrue(csv.contains("\"\(formatter.string(from: date))\""))
    XCTAssertTrue(csv.contains(",\"1.5\",\"\"\r\n"))
    XCTAssertEqual(HistoryExport.minutes(1500), "25")
  }

  func testMissingProjectAndEmptyHistoryAreExplicit() {
    let csv = HistoryExport.csv(records: [record(projectID: UUID())], projects: [])
    XCTAssertTrue(csv.hasSuffix(",\"Deleted project\"\r\n"))
    XCTAssertEqual(
      HistoryExport.csv(records: [], projects: []),
      "intention,started_at,completed_at,duration_minutes,project\r\n")
  }

  func testNewestSessionsExportFirst() {
    let newer = record(title: "New", completedAt: date.addingTimeInterval(3600))
    let older = record(title: "Old")
    let rows = HistoryExport.csv(records: [older, newer], projects: []).components(
      separatedBy: "\r\n")
    XCTAssertTrue(rows[1].hasPrefix("\"New\","))
    XCTAssertTrue(rows[2].hasPrefix("\"Old\","))
  }

  func testWeekUsesLocalDaysAcrossDaylightSavingChange() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
    let firstDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28))!
    let lastDay = calendar.startOfDay(for: now)
    let entries = [
      record(title: "Before", completedAt: firstDay.addingTimeInterval(-1)),
      record(title: "First", duration: 600, completedAt: firstDay),
      record(title: "Last", duration: 1200, completedAt: lastDay),
      record(title: "Tomorrow", completedAt: calendar.date(byAdding: .day, value: 1, to: lastDay)!),
    ]
    let week = HistoryWeek(records: entries, now: now, calendar: calendar)
    XCTAssertEqual(week.days.count, 7)
    XCTAssertEqual(week.days.first?.date, firstDay)
    XCTAssertEqual(week.days.last?.date, lastDay)
    XCTAssertEqual(week.records.count, 2)
    XCTAssertEqual(week.seconds, 1800)
    XCTAssertEqual(week.averageSeconds, 900)
    XCTAssertEqual(week.days.filter { $0.seconds == 0 }.count, 5)
    XCTAssertTrue(
      zip(week.days, week.days.dropFirst()).contains { next in
        next.1.date.timeIntervalSince(next.0.date) == 25 * 3600
      })
  }

  func testEmptyWeekHasZeroTotalsWithoutInventedActivity() {
    let week = HistoryWeek(records: [], now: date)
    XCTAssertEqual(week.days.count, 7)
    XCTAssertEqual(week.seconds, 0)
    XCTAssertEqual(week.averageSeconds, 0)
    XCTAssertTrue(week.days.allSatisfy { $0.records.isEmpty && $0.seconds == 0 })
  }

  func testSearchFindsTitlesAndProjectsIgnoringCaseAndAccents() {
    let project = Project(name: "Café website")
    let titled = record(title: "Review onboarding")
    let assigned = record(title: "Build navigation", projectID: project.id)
    let unrelated = record(title: "Write release notes")
    let records = [titled, assigned, unrelated]
    XCTAssertEqual(
      HistorySearch.filter(records: records, projects: [project], query: "  ONBOARD  ").map(\.id),
      [titled.id])
    XCTAssertEqual(
      HistorySearch.filter(records: records, projects: [project], query: "cafe").map(\.id),
      [assigned.id])
    XCTAssertTrue(
      HistorySearch.filter(records: records, projects: [project], query: "missing").isEmpty)
    XCTAssertEqual(
      HistorySearch.filter(records: records, projects: [project], query: " \n\t"), records)
  }

  func testSearchMatchesDisplayedFallbackLabels() {
    let untitled = record(title: "")
    let deletedProject = record(projectID: UUID())
    XCTAssertEqual(
      HistorySearch.filter(records: [untitled, deletedProject], projects: [], query: "Untitled")
        .map(\.id),
      [untitled.id])
    XCTAssertEqual(
      HistorySearch.filter(
        records: [untitled, deletedProject], projects: [], query: "Deleted project"
      ).map(\.id),
      [deletedProject.id])
  }

  func testFilteredExportIncludesOnlyMatchingRecordsWithinSelectedScope() {
    let week = HistoryWeek(
      records: [
        record(title: "Keep"), record(title: "Exclude"),
        record(title: "Keep old", completedAt: date.addingTimeInterval(-10 * 86400)),
      ],
      now: date)
    let filtered = HistorySearch.filter(records: week.records, projects: [], query: "Keep")
    let csv = HistoryExport.csv(records: filtered, projects: [])
    XCTAssertEqual(filtered.count, 1)
    XCTAssertTrue(csv.contains("\"Keep\","))
    XCTAssertFalse(csv.contains("Exclude"))
    XCTAssertFalse(csv.contains("Keep old"))
  }

  private func record(
    title: String = "Write", duration: TimeInterval = 1500, projectID: UUID? = nil,
    completedAt: Date? = nil
  ) -> SessionRecord {
    let completion = completedAt ?? date
    return SessionRecord(
      intention: title, duration: duration, startedAt: completion.addingTimeInterval(-duration),
      completedAt: completion, projectID: projectID)
  }
}

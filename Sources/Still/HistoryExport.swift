import Foundation
import StillCore

enum HistoryExport {
  static func csv(records: [SessionRecord], projects: [Project]) -> String {
    let projectNames = Dictionary(
      projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let dates = ISO8601DateFormatter()
    dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let rows = records.sorted { $0.completedAt > $1.completedAt }.map { record in
      let project = record.projectID.map { projectNames[$0] ?? "Deleted project" } ?? ""
      return [
        field(record.intention),
        field(dates.string(from: record.startedAt)),
        field(dates.string(from: record.completedAt)),
        field(minutes(record.duration)),
        field(project),
      ].joined(separator: ",")
    }
    return (["intention,started_at,completed_at,duration_minutes,project"] + rows)
      .joined(separator: "\r\n") + "\r\n"
  }

  static func minutes(_ duration: TimeInterval) -> String {
    (duration / 60).formatted(
      .number.grouping(.never).precision(.fractionLength(0...6))
        .locale(Locale(identifier: "en_US_POSIX")))
  }

  private static func field(_ value: String) -> String {
    let dangerous = CharacterSet(charactersIn: "=+-@\t\r\n")
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    let needsPrefix =
      value.unicodeScalars.first.map(dangerous.contains) == true
      || trimmed.unicodeScalars.first.map(dangerous.contains) == true
    let safe = needsPrefix ? "'" + value : value
    return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}

enum HistorySearch {
  static func filter(records: [SessionRecord], projects: [Project], query: String)
    -> [SessionRecord]
  {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return records }
    let projectNames = Dictionary(
      projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    return records.filter { record in
      let title = record.intention.isEmpty ? "Untitled session" : record.intention
      let project = record.projectID.map { projectNames[$0] ?? "Deleted project" } ?? ""
      return [title, project].contains { value in
        value.range(
          of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
      }
    }
  }
}

struct HistoryWeek {
  struct Day: Identifiable {
    let date: Date
    let records: [SessionRecord]
    var id: Date { date }
    var seconds: TimeInterval { records.reduce(0) { $0 + $1.duration } }
  }

  let days: [Day]
  var records: [SessionRecord] { days.flatMap(\.records) }
  var seconds: TimeInterval { days.reduce(0) { $0 + $1.seconds } }
  var averageSeconds: TimeInterval { records.isEmpty ? 0 : seconds / Double(records.count) }

  init(records: [SessionRecord], now: Date, calendar: Calendar = .current) {
    let today = calendar.startOfDay(for: now)
    let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.completedAt) }
    days = (-6...0).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
      return Day(date: day, records: grouped[day] ?? [])
    }
  }
}

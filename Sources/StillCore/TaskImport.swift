import Foundation

public struct ImportedTask: Codable, Equatable, Sendable {
  public let title: String
  public let isComplete: Bool

  public init(title: String, isComplete: Bool = false) {
    self.title = title
    self.isComplete = isComplete
  }
}

/// Imports local text without interpreting links, HTML, commands, or other markup.
public enum TaskImport {
  public static let maximumCharacters = 200_000
  public static let maximumTasks = 500

  public enum ImportError: Error, Equatable, LocalizedError, Sendable {
    case tooLarge
    case tooManyTasks

    public var errorDescription: String? {
      switch self {
      case .tooLarge:
        return "This text is too large. Import up to 200,000 characters at a time."
      case .tooManyTasks:
        return "This list contains too many tasks. Import up to 500 tasks at a time."
      }
    }
  }

  /// If any list items exist, surrounding prose is excluded. Otherwise, each text line is a task.
  public static func parse(_ text: String) throws -> [ImportedTask] {
    guard text.count <= maximumCharacters else { throw ImportError.tooLarge }
    var plainLines: [String] = []
    var listTasks: [ImportedTask] = []
    var foundList = false
    var fence: (character: Character, length: Int)?

    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }

      if let activeFence = fence {
        let prefix = line.prefix(while: { $0 == activeFence.character })
        if prefix.count >= activeFence.length,
          line.dropFirst(prefix.count).allSatisfy(\.isWhitespace)
        {
          fence = nil
        }
        continue
      }
      if let first = line.first, first == "`" || first == "~" {
        let runLength = line.prefix(while: { $0 == first }).count
        if runLength >= 3 {
          fence = (first, runLength)
          continue
        }
      }
      if isHeading(line) { continue }

      if let content = listContent(line) {
        foundList = true
        plainLines.removeAll(keepingCapacity: false)
        let task = checkboxTask(content)
        if !task.title.isEmpty {
          listTasks.append(task)
          guard listTasks.count <= maximumTasks else { throw ImportError.tooManyTasks }
        }
      } else if !foundList {
        // Keep only enough plain lines to report overflow. A later list can still exclude them.
        if plainLines.count <= maximumTasks { plainLines.append(line) }
      }
    }

    if foundList { return listTasks }
    guard plainLines.count <= maximumTasks else { throw ImportError.tooManyTasks }
    return plainLines.map { ImportedTask(title: $0) }
  }

  private static func isHeading(_ line: String) -> Bool {
    guard line.first == "#" else { return false }
    let remainder = line.drop(while: { $0 == "#" })
    return remainder.first?.isWhitespace ?? true
  }

  private static func listContent(_ line: String) -> String? {
    guard let first = line.first else { return nil }
    var remainder: Substring
    if first == "-" || first == "*" || first == "+" {
      remainder = line.dropFirst()
    } else {
      let digits = line.prefix { character in
        guard let ascii = character.asciiValue else { return false }
        return (48...57).contains(ascii)
      }
      guard !digits.isEmpty else { return nil }
      remainder = line.dropFirst(digits.count)
      guard remainder.first == "." || remainder.first == ")" else { return nil }
      remainder = remainder.dropFirst()
    }
    guard remainder.first?.isWhitespace ?? true else { return nil }
    return remainder.trimmingCharacters(in: .whitespaces)
  }

  private static func checkboxTask(_ content: String) -> ImportedTask {
    let prefix = content.prefix(3)
    guard prefix == "[ ]" || prefix == "[x]" || prefix == "[X]" else {
      return ImportedTask(title: content)
    }
    let remainder = content.dropFirst(3)
    guard remainder.first?.isWhitespace ?? true else { return ImportedTask(title: content) }
    return ImportedTask(
      title: remainder.trimmingCharacters(in: .whitespaces),
      isComplete: prefix != "[ ]")
  }
}

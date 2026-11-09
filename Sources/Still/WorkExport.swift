import Foundation
import StillCore

enum WorkExport {
  static func brief(task: TaskItem, project: Project?) -> String {
    var sections = ["# \(task.title)"]
    if let project { sections.append("Project: \(project.name)") }
    sections.append("Session length: \(task.estimateMinutes) minutes")
    if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      sections.append("## Notes\n\(task.notes)")
    }
    if !task.links.isEmpty {
      sections.append(
        "## References\n"
          + task.links.map { link in
            link.title.isEmpty ? "- \(link.url)" : "- \(link.title)\n  \(link.url)"
          }.joined(separator: "\n"))
    }
    return sections.joined(separator: "\n\n") + "\n"
  }

  static func checklist(tasks: [TaskItem]) -> String {
    tasks.map { task in
      "- [\(task.isComplete ? "x" : " ")] \(task.title.replacingOccurrences(of: "\n", with: " "))"
    }.joined(separator: "\n") + (tasks.isEmpty ? "" : "\n")
  }
}

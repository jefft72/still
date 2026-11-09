import Foundation

/// A local handoff to Still. Parsing does not create data, open URLs, or run commands.
public enum StillURLAction: Equatable, Sendable {
  case task(title: String, notes: String, project: String?, minutes: Int, reference: URL?)
  case note(String)

  /// Unknown query parameters are ignored so newer clients can send older apps a handoff.
  /// Parameter names are case-sensitive; duplicate names are always rejected.
  public static func parse(_ url: URL) throws -> StillURLAction {
    guard url.absoluteString.utf8.count <= 200_000 else { throw StillURLError.tooLong }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw StillURLError.malformedURL
    }
    guard components.scheme?.lowercased() == "still" else { throw StillURLError.invalidScheme }
    guard components.user == nil, components.password == nil, components.port == nil else {
      throw StillURLError.unexpectedAuthority
    }
    guard components.path.isEmpty || components.path == "/" else {
      throw StillURLError.unexpectedPath
    }
    guard components.fragment == nil else { throw StillURLError.unexpectedFragment }
    guard let action = components.host?.lowercased(), ["task", "note"].contains(action) else {
      throw StillURLError.unknownAction
    }

    var parameters: [String: String] = [:]
    var names: Set<String> = []
    for item in components.queryItems ?? [] {
      guard names.insert(item.name).inserted else {
        throw StillURLError.duplicateParameter(item.name)
      }
      parameters[item.name] = item.value ?? ""
    }
    func required(_ name: String) throws -> String {
      let value = parameters[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !value.isEmpty else { throw StillURLError.missingValue(name) }
      return value
    }

    if action == "note" { return .note(try required("text")) }

    let title = try required("title")
    let minutes: Int
    if let value = parameters["minutes"] {
      guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(value), (1...180).contains(number)
      else { throw StillURLError.invalidMinutes }
      minutes = number
    } else {
      minutes = 25
    }

    var reference: URL?
    if let value = parameters["url"] {
      guard let target = URLComponents(string: value),
        let scheme = target.scheme?.lowercased(), ["https", "http"].contains(scheme),
        let host = target.host, !host.isEmpty,
        target.user == nil, target.password == nil,
        let targetURL = target.url
      else { throw StillURLError.unsafeReference }
      reference = targetURL
    }
    let project = parameters["project"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .task(
      title: title,
      notes: parameters["notes"] ?? "",
      project: project.flatMap { $0.isEmpty ? nil : $0 },
      minutes: minutes,
      reference: reference)
  }
}

public enum StillURLError: Error, Equatable, LocalizedError, Sendable {
  case tooLong
  case malformedURL
  case invalidScheme
  case unexpectedAuthority
  case unexpectedPath
  case unexpectedFragment
  case unknownAction
  case duplicateParameter(String)
  case missingValue(String)
  case invalidMinutes
  case unsafeReference

  public var errorDescription: String? {
    switch self {
    case .tooLong:
      return "This Still link exceeds the 200,000-byte limit."
    case .malformedURL:
      return "This Still link couldn't be read."
    case .invalidScheme:
      return "A Still link must start with still://."
    case .unexpectedAuthority:
      return "Still links cannot contain a username, password, or port."
    case .unexpectedPath:
      return "Still links use query parameters after still://task or still://note, without a path."
    case .unexpectedFragment:
      return "Encode # as %23 inside a Still link's text. URL fragments aren't supported."
    case .unknownAction:
      return "This Still link must use the task or note action."
    case .duplicateParameter(let name):
      return "The Still link contains more than one '\(name)' parameter."
    case .missingValue(let name):
      return "The Still link needs a nonempty '\(name)' parameter."
    case .invalidMinutes:
      return "The session duration must be a whole number from 1 to 180 minutes."
    case .unsafeReference:
      return
        "A task reference must be an HTTP or HTTPS URL with a host and no embedded credentials."
    }
  }
}

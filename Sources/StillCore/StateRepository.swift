import Foundation

/// Versioned, atomic storage. A damaged or newer file is reported, never replaced by load().
public struct StateRepository: Sendable {
  public enum StorageError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidSession

    public var errorDescription: String? {
      switch self {
      case .unsupportedVersion(let version):
        return "This data was saved by a newer version of Still (format \(version))."
      case .invalidSession:
        return "The saved session is damaged. Your original data has been kept."
      }
    }
  }

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static func applicationDefault() throws -> StateRepository {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return StateRepository(
      fileURL: base.appendingPathComponent("Still", isDirectory: true).appendingPathComponent(
        "state.json"))
  }

  public func load() throws -> StillState {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return StillState() }
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    let version = try decoder.decode(Version.self, from: data)
    guard (1...2).contains(version.version) else {
      throw StorageError.unsupportedVersion(version.version)
    }
    let state = try decoder.decode(Envelope.self, from: data).state
    guard state.session.isValidPersistedState, state.isValidWorkspace,
      Set(state.thoughts.map(\.id)).count == state.thoughts.count,
      Set(state.history.map(\.id)).count == state.history.count,
      state.thoughts.allSatisfy({
        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && $0.createdAt.timeIntervalSince1970.isFinite
      }),
      state.history.allSatisfy({
        $0.duration.isFinite && (1...10_800).contains($0.duration)
          && $0.startedAt.timeIntervalSince1970.isFinite
          && $0.completedAt.timeIntervalSince1970.isFinite
          && $0.completedAt >= $0.startedAt
      })
    else { throw StorageError.invalidSession }
    return state
  }

  public func save(_ state: StillState) throws {
    let parent = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Envelope(version: 2, state: state))
    try data.write(to: fileURL, options: .atomic)
  }

  private struct Version: Decodable { let version: Int }
  private struct Envelope: Codable {
    let version: Int
    let state: StillState
  }
}

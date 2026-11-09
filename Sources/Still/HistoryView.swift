import AppKit
import StillCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
  @ObservedObject var store: AppStore
  @State private var scope = Scope.week
  @State private var query = ""
  @State private var exportError: String?

  private enum Scope: String, CaseIterable, Identifiable {
    case week = "Last 7 days"
    case all = "All time"
    var id: String { rawValue }
  }

  var body: some View {
    let week = HistoryWeek(records: store.state.history, now: store.now)
    let records = scope == .week ? week.records : store.state.history
    VStack(alignment: .leading, spacing: 28) {
      weeklySummary(week)
      sessionList(records)
    }
    .background(Palette.background)
    .alert(
      "Couldn't export sessions",
      isPresented: Binding(
        get: { exportError != nil },
        set: { if !$0 { exportError = nil } }
      )
    ) {
      Button("OK") { exportError = nil }
    } message: {
      Text(exportError ?? "")
    }
  }

  private func weeklySummary(_ week: HistoryWeek) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Last 7 days").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.ink)
        Spacer()
        if let first = week.days.first, let last = week.days.last {
          Text(
            "\(first.date.formatted(.dateTime.month(.abbreviated).day())) - \(last.date.formatted(.dateTime.month(.abbreviated).day()))"
          )
          .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
      }
      HStack(spacing: 16) {
        statistic(number: minuteLabel(week.seconds), label: "Minutes focused")
        Rectangle().fill(Palette.line).frame(width: 1, height: 34)
        statistic(number: "\(week.records.count)", label: "Sessions completed")
        Rectangle().fill(Palette.line).frame(width: 1, height: 34)
        statistic(number: minuteLabel(week.averageSeconds), label: "Average minutes")
        Spacer(minLength: 0)
      }
      weekChart(week)
    }
  }

  private func statistic(number: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(number).font(.system(size: 25, weight: .semibold)).monospacedDigit()
        .foregroundStyle(Palette.ink)
      Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label): \(number)")
  }

  private func weekChart(_ week: HistoryWeek) -> some View {
    let maximum = week.days.map(\.seconds).max() ?? 0
    return VStack(spacing: 8) {
      HStack {
        Text("Daily minutes")
        Spacer()
        if maximum > 0 { Text("\(minuteLabel(maximum)) max") }
      }
      .font(.system(size: 10)).foregroundStyle(Palette.muted)
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          Rectangle().fill(Palette.line.opacity(0.55)).frame(height: 1)
          Spacer()
          Rectangle().fill(Palette.line.opacity(0.55)).frame(height: 1)
          Spacer()
          Rectangle().fill(Palette.line).frame(height: 1)
        }
        HStack(alignment: .bottom, spacing: 18) {
          ForEach(week.days) { day in
            RoundedRectangle(cornerRadius: 3)
              .fill(Palette.ink.opacity(0.72))
              .frame(width: 22, height: maximum > 0 ? day.seconds / maximum * 100 : 0)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
              .contentShape(Rectangle())
              .help(
                "\(day.date.formatted(date: .complete, time: .omitted)): \(minuteLabel(day.seconds)) \(minuteLabel(day.seconds) == "1" ? "minute" : "minutes"), \(day.records.count) \(day.records.count == 1 ? "session" : "sessions")"
              )
              .accessibilityLabel(
                "\(day.date.formatted(date: .complete, time: .omitted)), \(minuteLabel(day.seconds)) \(minuteLabel(day.seconds) == "1" ? "minute" : "minutes"), \(day.records.count) \(day.records.count == 1 ? "session" : "sessions")"
              )
          }
        }
      }
      .frame(height: 100)
      HStack(spacing: 18) {
        ForEach(week.days) { day in
          Text(day.date, format: .dateTime.weekday(.abbreviated))
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Focus time over the last seven days")
  }

  private func sessionList(_ records: [SessionRecord]) -> some View {
    let filtered = HistorySearch.filter(
      records: records, projects: store.state.projects, query: query)
    let groups = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.completedAt) }
    let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 14) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 16) {
            listTitle(count: filtered.count, total: records.count, searching: searching)
              .fixedSize()
            Spacer(minLength: 0)
            listActions(filtered).fixedSize()
          }
          VStack(alignment: .leading, spacing: 12) {
            listTitle(count: filtered.count, total: records.count, searching: searching)
            HStack {
              listActions(filtered)
              Spacer(minLength: 0)
            }
          }
        }
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").font(.system(size: 11))
            .foregroundStyle(Palette.muted)
          TextField("Search sessions or projects", text: $query)
            .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.ink)
            .accessibilityLabel("Search session history")
            .accessibilityIdentifier("history-search")
            .onExitCommand { query = "" }
          if !query.isEmpty {
            Button {
              query = ""
            } label: {
              Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain).accessibilityLabel("Clear history search")
          }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
      }
      if filtered.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            searching
              ? "No matching sessions."
              : scope == .week ? "No sessions in the last 7 days." : "No completed sessions."
          )
          .font(.system(size: 13)).foregroundStyle(Palette.ink)
          Text(
            searching
              ? "Try another title or project, or change the time range."
              : "Finish a focus session to see it here."
          )
          .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }.padding(.vertical, 18)
      } else {
        LazyVStack(alignment: .leading, spacing: 24) {
          ForEach(groups.keys.sorted(by: >), id: \.self) { day in
            VStack(alignment: .leading, spacing: 4) {
              Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                .padding(.bottom, 5)
              ForEach((groups[day] ?? []).sorted { $0.completedAt > $1.completedAt }) { record in
                sessionRow(record)
              }
            }
          }
        }
      }
    }
  }

  private func listTitle(count: Int, total: Int, searching: Bool) -> some View {
    HStack(spacing: 8) {
      Text("Completed sessions").font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.ink)
      Text(searching ? "\(count) of \(total)" : "\(count)")
        .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
        .accessibilityLabel(
          searching
            ? "\(count) matching sessions out of \(total)"
            : "\(count) \(count == 1 ? "session" : "sessions")")
    }
  }

  private func listActions(_ records: [SessionRecord]) -> some View {
    HStack(spacing: 10) {
      Picker("Session history period", selection: $scope) {
        ForEach(Scope.allCases) { item in Text(item.rawValue).tag(item) }
      }
      .pickerStyle(.segmented).labelsHidden().frame(width: 170)
      Button {
        export(records)
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
          .font(.system(size: 11))
      }
      .buttonStyle(QuietButton()).disabled(records.isEmpty)
      .help("Export \(records.count) \(records.count == 1 ? "session" : "sessions") as CSV")
    }
  }

  private func sessionRow(_ record: SessionRecord) -> some View {
    HStack(spacing: 14) {
      Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
        .foregroundStyle(Palette.green).frame(width: 16).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(record.intention.isEmpty ? "Untitled session" : record.intention)
          .font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(2)
        if let id = record.projectID {
          Text(store.state.projects.first { $0.id == id }?.name ?? "Deleted project")
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
      }
      Spacer(minLength: 12)
      Text(record.completedAt, format: .dateTime.hour().minute())
        .font(.system(size: 11)).foregroundStyle(Palette.muted)
      Text("\(minuteLabel(record.duration)) min")
        .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.ink)
        .frame(minWidth: 52, alignment: .trailing)
    }
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    .textSelection(.enabled)
  }

  private func minuteLabel(_ seconds: TimeInterval) -> String {
    (seconds / 60).formatted(.number.precision(.fractionLength(0...1)))
  }

  @MainActor
  private func export(_ records: [SessionRecord]) {
    let csv = HistoryExport.csv(records: records, projects: store.state.projects)
    let panel = NSSavePanel()
    panel.title = "Export sessions"
    panel.prompt = "Export"
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "still-sessions.csv"
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try csv.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        exportError = error.localizedDescription
      }
    }
  }
}

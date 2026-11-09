import SwiftUI

struct SessionStrip: View {
  @ObservedObject var store: AppStore
  @State private var showingDuration = false
  @State private var duration = 25
  @State private var confirmingReset = false
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 22) {
        VStack(alignment: .leading, spacing: 9) {
          HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(statusLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(
              Palette.muted)
          }
          if store.isActive {
            Text(store.intention).font(.system(size: compact ? 14 : 18, weight: .medium))
              .foregroundStyle(Palette.ink).lineLimit(2)
          } else {
            TextField(
              "What are you working on?",
              text: Binding(get: { store.state.session.intention }, set: store.setIntention)
            )
            .textFieldStyle(.plain).font(.system(size: compact ? 14 : 18, weight: .medium))
            .foregroundStyle(Palette.ink).accessibilityLabel("Session intention")
            .onSubmit(store.primaryAction)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Text(store.timeString).font(
          .system(size: compact ? 32 : 42, weight: .light, design: .monospaced)
        )
        .tracking(-2).foregroundStyle(Palette.ink).monospacedDigit()
        .accessibilityLabel("\(store.timeString) remaining")
      }
      HStack(spacing: 10) {
        Button(action: store.primaryAction) {
          Label(actionLabel, systemImage: store.actionSymbol).lineLimit(1).fixedSize()
        }.buttonStyle(PrimaryButton()).accessibilityIdentifier("session-action")
        if store.isActive {
          Button {
            confirmingReset = true
          } label: {
            Text("End session").font(.system(size: 12))
          }
          .buttonStyle(QuietButton())
        } else {
          Button {
            duration = max(1, Int(store.state.session.duration / 60))
            showingDuration = true
          } label: {
            HStack(spacing: 5) {
              Text("\(Int(store.state.session.duration / 60)) min")
              Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.font(.system(size: 12))
          }.buttonStyle(QuietButton()).accessibilityLabel("Session duration")
            .popover(isPresented: $showingDuration) {
              VStack(alignment: .leading, spacing: 18) {
                Text("Session duration").font(.system(size: 13, weight: .semibold))
                HStack {
                  ForEach([15, 25, 45, 60], id: \.self) { value in
                    Button("\(value)m") {
                      store.setDuration(value)
                      showingDuration = false
                    }
                    .buttonStyle(QuietButton(selected: duration == value))
                  }
                }
                HStack {
                  TextField("Minutes", value: $duration, format: .number).frame(width: 65)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Custom minutes")
                  Text("minutes").font(.system(size: 12)).foregroundStyle(Palette.muted)
                  Spacer()
                  Button("Set") {
                    store.setDuration(min(180, max(1, duration)))
                    showingDuration = false
                  }
                  .buttonStyle(PrimaryButton())
                }
                Text("1 to 180 minutes").font(.system(size: 11)).foregroundStyle(Palette.muted)
              }.padding(20).frame(width: 280).background(Palette.background).preferredColorScheme(
                .light)
            }
        }
        Spacer()
        if store.state.session.phase == .finished {
          Label("Session saved", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(
            Palette.green)
        }
      }
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Rectangle().fill(Palette.line)
          Rectangle().fill(statusColor)
            .frame(width: geometry.size.width * store.state.session.progress(at: store.now))
        }
      }.frame(height: 2)
    }
    .confirmationDialog(
      "End this session?", isPresented: $confirmingReset, titleVisibility: .visible
    ) {
      Button("End session", role: .destructive) { store.reset() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This session won't be added to your history. Your tasks and notes are saved.")
    }
  }

  private var actionLabel: String {
    switch store.state.session.phase {
    case .idle: compact ? "Start" : "Start session"
    case .running: compact ? "Pause" : "Pause session"
    case .paused: compact ? "Resume" : "Resume session"
    case .finished: "Start again"
    }
  }
  private var statusLabel: String {
    switch store.state.session.phase {
    case .idle: "Focus session"
    case .running: "In progress"
    case .paused: "Paused"
    case .finished: "Completed"
    }
  }
  private var statusColor: Color {
    switch store.state.session.phase {
    case .idle, .paused: Palette.muted
    case .running: Palette.accent
    case .finished: Palette.green
    }
  }
}

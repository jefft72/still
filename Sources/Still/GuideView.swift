import SwiftUI

struct GuideView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 10) {
        StillMark()
        Text("Still").font(.system(size: 20, weight: .semibold))
        Spacer()
      }
      Text("Plan your work, then start a session.").font(.system(size: 16, weight: .medium))
      Text(
        "Add tasks to Today, or keep them in Inbox for later. Projects group related tasks. Each task can hold notes, files, and links."
      )
      .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted)
      Divider()
      row("Search tasks and projects", "⌘ K")
      row("New task", "⌘ N")
      row("New note", "⌘ ⇧ N")
      row("Start, pause, or resume", "⌘ Return")
      row("Mini player", "⌘ ⇧ M")
      row("Open workspace", "⌘ 1")
      Divider()
      Text(
        "The timer continues while Still is closed or your Mac sleeps. Pause before stepping away. Only completed sessions appear in History; completing a session doesn't check off its task."
      )
      .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted)
      Text(
        "Your data stays on this Mac. Background sound is optional and always starts muted when you open Still."
      )
      .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
      }
    }.padding(30).frame(width: 440).background(Palette.background).foregroundStyle(Palette.ink)
      .preferredColorScheme(.light)
  }
  private func row(_ title: String, _ key: String) -> some View {
    HStack {
      Text(title).font(.system(size: 12))
      Spacer()
      Text(key).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
    }
  }
}

import AppKit
import SwiftUI

@main
struct StillApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var store: AppStore

  init() {
    let model = AppStore()
    _store = StateObject(wrappedValue: model)
    AppDelegate.model = model
  }

  var body: some Scene {
    Window("Still", id: "main") {
      MainView(store: store)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    .defaultSize(width: 1060, height: 720)
    .defaultPosition(.center)
    .commands { StillCommands(store: store) }

    Window("Still Mini", id: "mini") {
      MiniView(store: store)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultPosition(.topTrailing)

    MenuBarExtra {
      StillMenu(store: store)
    } label: {
      Image(
        systemName: store.state.session.phase == .finished ? "checkmark.circle" : "pause.circle")
      if store.isActive {
        Text(store.timeString).monospacedDigit()
      } else if store.state.session.phase == .finished {
        Text("Done")
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var reopen: (() -> Void)?
  static var model: AppStore?
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { Self.model?.handleURL(url) }
    Self.reopen?()
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { Self.reopen?() }
    return true
  }
}

struct StillCommands: Commands {
  @ObservedObject var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Task") {
        openWorkspace()
        store.focusRequest = .task
      }.keyboardShortcut("n")
      Button("New Note") {
        openWorkspace()
        store.focusRequest = .note
      }.keyboardShortcut("n", modifiers: [.command, .shift])
    }
    CommandGroup(after: .importExport) {
      Button("Import Tasks…") {
        openWorkspace()
        store.showingImport = true
      }
      .keyboardShortcut("i", modifiers: [.command, .shift])
    }
    CommandGroup(after: .textEditing) {
      Button("Search Tasks and Projects") {
        openWorkspace()
        store.showingCommandPalette = true
      }
      .keyboardShortcut("k")
    }
    CommandMenu("Focus") {
      Button(store.actionTitle, action: store.primaryAction).keyboardShortcut(.return)
      Divider()
      Button("Open Workspace", action: openWorkspace).keyboardShortcut("1")
      Button("Mini Player") {
        openWindow(id: "mini")
        dismissWindow(id: "main")
      }.keyboardShortcut("m", modifiers: [.command, .shift])
    }
    CommandGroup(replacing: .help) {
      Button("Still Help") {
        openWorkspace()
        store.showingGuide = true
      }
    }
  }
  private func openWorkspace() {
    openWindow(id: "main")
    dismissWindow(id: "mini")
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct StillMenu: View {
  @ObservedObject var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  var body: some View {
    Text(store.intention)
    Text(
      store.state.session.phase == .finished ? "Session complete" : "\(store.timeString) remaining")
    Divider()
    Button(store.actionTitle, action: store.primaryAction)
    Button("Open Still") {
      openWindow(id: "main")
      dismissWindow(id: "mini")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("Mini Player") {
      openWindow(id: "mini")
      dismissWindow(id: "main")
    }
    Divider()
    Button("Quit Still") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
}

struct MiniView: View {
  @ObservedObject var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        StillMark(size: 15)
        Text("Still").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
        Spacer()
        Button {
          openWindow(id: "main")
          dismissWindow(id: "mini")
        } label: {
          Image(systemName: "pip.exit")
        }
        .buttonStyle(IconButton()).help("Open workspace").accessibilityLabel("Open workspace")
      }
      SessionStrip(store: store, compact: true)
    }.padding(20).frame(width: 380).background(Palette.background)
      .background(WindowConfigurator(floating: true)).preferredColorScheme(.light)
      .onAppear {
        AppDelegate.reopen = {
          openWindow(id: "main")
          dismissWindow(id: "mini")
        }
        if store.focusRequest != nil {
          openWindow(id: "main")
          dismissWindow(id: "mini")
        }
      }
      .onChange(of: store.focusRequest) { _, request in
        if request != nil {
          openWindow(id: "main")
          dismissWindow(id: "mini")
        }
      }
  }
}

struct WindowConfigurator: NSViewRepresentable {
  let floating: Bool
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { configure(view.window) }
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { configure(nsView.window) }
  }
  private func configure(_ window: NSWindow?) {
    guard let window else { return }
    window.titlebarAppearsTransparent = true
    window.backgroundColor = NSColor(Palette.background)
    window.isMovableByWindowBackground = true
    window.level = floating ? .floating : .normal
    if floating { window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
  }
}

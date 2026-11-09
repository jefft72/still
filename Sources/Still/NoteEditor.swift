import AppKit
import SwiftUI

struct NoteEditor: NSViewRepresentable {
  @Binding var text: String
  let focusRequest: Int
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
    editor.isRichText = false
    editor.importsGraphics = false
    editor.isEditable = true
    editor.isSelectable = true
    editor.allowsUndo = true
    editor.drawsBackground = false
    editor.font = .systemFont(ofSize: 12)
    editor.textColor = NSColor(Palette.ink)
    editor.insertionPointColor = NSColor(Palette.ink)
    editor.textContainerInset = .zero
    editor.textContainer?.lineFragmentPadding = 0
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.containerSize = NSSize(
      width: 200, height: CGFloat.greatestFiniteMagnitude)
    editor.isHorizontallyResizable = false
    editor.isVerticallyResizable = true
    editor.autoresizingMask = [.width]
    editor.minSize = NSSize(width: 0, height: 60)
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticLinkDetectionEnabled = false
    editor.setAccessibilityLabel("New note")
    editor.setAccessibilityIdentifier("note-input")
    editor.string = text
    editor.delegate = context.coordinator
    editor.onSubmit = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onSubmit()
    }
    scrollView.documentView = editor
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let editor = scrollView.documentView as? NoteTextView else { return }
    if editor.string != text && !editor.hasMarkedText() {
      let selection = editor.selectedRange()
      context.coordinator.updatingFromBinding = true
      editor.string = text
      let length = (text as NSString).length
      let location = min(selection.location, length)
      editor.setSelectedRange(
        NSRange(location: location, length: min(selection.length, length - location)))
      editor.undoManager?.removeAllActions()
      if text.isEmpty { editor.scrollRangeToVisible(NSRange(location: 0, length: 0)) }
      context.coordinator.updatingFromBinding = false
    }
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      let request = focusRequest
      DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
        guard coordinator?.lastFocusRequest == request else { return }
        editor?.requestFocus()
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NoteEditor
    var lastFocusRequest = 0
    var updatingFromBinding = false

    init(parent: NoteEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard !updatingFromBinding, let editor = notification.object as? NSTextView else { return }
      parent.text = editor.string
    }
  }
}

private final class NoteTextView: NSTextView {
  var onSubmit: (() -> Void)?
  private var pendingFocus = false

  func requestFocus() {
    pendingFocus = true
    if let window, window.makeFirstResponder(self) { pendingFocus = false }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if pendingFocus, let window, window.makeFirstResponder(self) { pendingFocus = false }
  }

  override func keyDown(with event: NSEvent) {
    let isReturn = event.keyCode == 36 || event.keyCode == 76
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if isReturn && !hasMarkedText() {
      if modifiers.isEmpty {
        onSubmit?()
        return
      }
      if modifiers == .shift {
        insertText("\n", replacementRange: selectedRange())
        return
      }
    }
    // AppKit retains ownership of IME composition and modified shortcuts,
    // including Command-Return's application menu action.
    super.keyDown(with: event)
  }

  override func paste(_ sender: Any?) {
    pasteAsPlainText(sender)
  }
}

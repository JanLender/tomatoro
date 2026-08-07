import AppKit

/// Replaces the system pasteboard's contents with `text`. Shared by every
/// "Copy" context-menu item across the record/summary views.
func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

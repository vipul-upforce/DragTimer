import AppKit

// Explicit entry point — avoids @main + @MainActor async-entry issues
// and avoids NSApplicationMain overriding our pre-set delegate.
// This mirrors the pattern used in the minimal test that confirmed NSStatusItem works.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

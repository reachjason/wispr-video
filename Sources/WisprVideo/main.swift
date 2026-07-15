import AppKit

// Entry point. Menu-bar (accessory) app — no dock icon.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

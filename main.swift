import Cocoa

// This call bootstraps the Cocoa application using your Info.plist settings,
// which should point to your AppDelegate (or another principal class).
setvbuf(stdout, nil, _IONBF, 0)
setvbuf(stderr, nil, _IONBF, 0)

print("DEBUG: console")
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate

let _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

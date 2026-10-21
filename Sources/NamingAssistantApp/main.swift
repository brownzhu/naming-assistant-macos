import AppKit
import MacRenameCore

let application = NSApplication.shared
let applicationDelegate = NamingAssistantDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()

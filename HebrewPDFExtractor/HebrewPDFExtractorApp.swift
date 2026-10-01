import SwiftUI
import AppKit

@main
struct HebrewPDFExtractorApp: App {
    init() { DebugDriver.startIfRequested() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // SelectableTextView opts into AppKit's standard find-bar via `usesFindBar`, but
            // that only activates if something actually sends `performFindPanelAction:` — this is
            // the ⌘F menu item that does so, tagged to show the find interface specifically.
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 1 // NSTextFinder.Action.showFindInterface
                    NSApp.sendAction(Selector(("performFindPanelAction:")), to: nil, from: menuItem)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

import AppKit
import Carbon
import NotinhasCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NoteStore()
    private var controllers: [NoteWindowController] = []
    private var hotKeys: [HotKey] = []
    private var cornerTab: CornerTab?
    private var terminationSource: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = ProcessInfo.processInfo.environment["NOTINHAS_SNAPSHOT_DIR"] {
            Snapshot.render(into: directory)
            NSApp.terminate(nil)
            return
        }

        cornerTab = CornerTab { [weak self] in self?.showNotes() }
        let atLogin = launchedAsLoginItem
        store.loadAll().forEach { open($0) }
        placeNotesOnScreens()
        if controllers.isEmpty {
            // First run (or every note deleted): open straight into a fresh note, except at login.
            if !atLogin { createNote(near: nil) }
        } else if atLogin {
            controllers.forEach { $0.window.orderFrontRegardless() }
        } else {
            bringAllToFront()
        }

        hotKeys = [
            HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in self?.createNote(near: nil) },
            HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in self?.showNotes() },
        ].compactMap { $0 }
        LoginItem.enableOnFirstRun()
        terminateOnSIGTERM()
    }

    /// Opening the app again (Spotlight, Finder, `open`) while it runs brings every note forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showNotes()
        return false
    }

    /// A monitor was plugged in or out, or the screens were rearranged.
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        placeNotesOnScreens()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.flushPendingSave() }
    }

    /// ⌘N from the hidden main menu.
    @objc func newNote(_ sender: Any?) {
        createNote(near: controllers.first { $0.window.isKeyWindow })
    }

    /// ⌘Q from the hidden main menu.
    @objc func quitOrHide(_ sender: Any?) {
        if MainMenu.quitKeyHides {
            NSApp.hide(nil)
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: Notes

    @discardableResult
    private func open(_ note: Note) -> NoteWindowController {
        let controller = NoteWindowController(note: note)
        controller.onChange = { [weak self] in self?.save($0) }
        controller.onNewNote = { [weak self] in self?.createNote(near: $0) }
        controller.onDelete = { [weak self] in self?.delete($0) }
        controller.onShowAll = { [weak self] in self?.bringAllToFront() }
        controller.cornerTab = cornerTab
        controllers.append(controller)
        return controller
    }

    private func createNote(near source: NoteWindowController?) {
        let note = Note(frame: frameForNewNote(near: source?.window))
        save(note)
        let controller = open(note)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
        controller.focusBody()
    }

    private func delete(_ controller: NoteWindowController) {
        controller.close()
        controllers.removeAll { $0 === controller }
        store.delete(id: controller.note.id)
    }

    private func save(_ note: Note) {
        do {
            try store.save(note)
        } catch {
            NSLog("Notinhas: failed to save note \(note.id): \(error)")
        }
    }

    /// Every note forward, or a fresh one when there are none.
    private func showNotes() {
        if controllers.isEmpty {
            createNote(near: nil)
        } else {
            bringAllToFront()
        }
    }

    private func bringAllToFront() {
        let key = controllers.first { $0.window.isKeyWindow } ?? controllers.last
        for (index, controller) in controllers.enumerated() {
            controller.rise(after: Double(index) * 0.04)
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        controllers.forEach { $0.window.orderFrontRegardless() }
        key?.window.makeKeyAndOrderFront(nil)
    }

    /// Notes whose monitor is unplugged wait on the screen under the mouse and go back when it returns.
    private func placeNotesOnScreens() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first else { return }
        let targets = NotePlacement.targets(
            homes: controllers.map(\.note.frame),
            windows: controllers.map(\.window.frame),
            screens: NSScreen.screens.map(\.visibleFrame),
            fallback: screen.visibleFrame)
        for (controller, target) in zip(controllers, targets) {
            if let target { controller.window.setFrame(target, display: true) }
        }
    }

    /// Next to the note whose "+" was clicked, or cascading from the top-right of the screen under the mouse.
    private func frameForNewNote(near source: NSWindow?, size: CGSize = CGSize(width: 260, height: 240)) -> CGRect {
        if let source, let visible = source.screen?.visibleFrame {
            let top = source.frame.maxY - size.height
            let candidates = [
                CGRect(x: source.frame.maxX + 12, y: top, width: size.width, height: size.height),
                CGRect(x: source.frame.minX - 12 - size.width, y: top, width: size.width, height: size.height),
                CGRect(x: source.frame.minX + 28, y: top - 28, width: size.width, height: size.height),
            ]
            if let frame = candidates.first(where: { visible.contains($0) }) { return frame }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let step = CGFloat(controllers.count % 6) * 28
        return CGRect(
            x: visible.maxX - size.width - 48 - step,
            y: visible.maxY - size.height - 48 - step,
            width: size.width,
            height: size.height)
    }

    // MARK: System

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// `pkill` and the install script send SIGTERM; quit normally so pending edits are saved.
    private func terminateOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source
    }
}

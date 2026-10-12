import AppKit
import SwiftUI

/// The menubar icon: the app icon's mark, a boxed D (`Resources/AppIcon/menubar.svg`, drawn here from the same geometry
/// so it's sharp at any scale). While the model downloads or files index, a progress ring takes the box's place; while
/// indexing is paused, two bars take the D's (at full strength: a dimmed icon reads as "off", and search still works).
enum StatusIcon {
    /// `update`: a newer version is waiting, a dot at the box's top right.
    static func image(progress: Double?, paused: Bool = false, update: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            // The SVG's 64-unit grid, y down, so angles grow clockwise on screen.
            let grid = NSAffineTransform()
            grid.scale(by: rect.width / 64)
            grid.concat()
            if let progress {
                let center = NSPoint(x: 32, y: 32)
                let track = NSBezierPath()
                track.appendArc(withCenter: center, radius: 27, startAngle: 0, endAngle: 360)
                track.lineWidth = 5.3
                NSColor.black.withAlphaComponent(0.25).setStroke()
                track.stroke()
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 27, startAngle: -90,
                              endAngle: -90 + 360 * max(0.03, min(1, progress)), clockwise: false)
                arc.lineWidth = 5.3
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            } else {
                let box = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.5, width: 55, height: 55), xRadius: 12, yRadius: 12)
                for (from, to) in [((32, 5), (32, 16)), ((32, 48), (32, 59)), ((5, 32), (17, 32)), ((47, 32), (59, 32))] {
                    box.move(to: NSPoint(x: from.0, y: from.1))
                    box.line(to: NSPoint(x: to.0, y: to.1))
                }
                box.lineWidth = 4.5
                NSColor.black.setStroke()
                box.stroke()
            }
            NSColor.black.setFill()
            if paused, progress == nil {
                for x in [23.5, 34.5] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: 21, width: 6, height: 22), xRadius: 1.8, yRadius: 1.8).fill()
                }
            } else {
                letter.fill()
            }
            if update {
                // Cut a gap around it, so it reads as a dot on the mark and not part of it.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 41, y: -1, width: 24, height: 24)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 46, y: 4, width: 14, height: 14)).fill()
            }
            return true
        }
        image.isTemplate = true   // takes the menubar's color, light or dark
        image.accessibilityDescription = "DigUp"
        return image
    }

    /// The D: a stem with rounded corners and a half circle.
    private static var letter: NSBezierPath {
        let d = NSBezierPath()
        d.move(to: NSPoint(x: 25, y: 21))
        d.line(to: NSPoint(x: 30, y: 21))
        d.appendArc(withCenter: NSPoint(x: 30, y: 32), radius: 11, startAngle: -90, endAngle: 90, clockwise: false)
        d.line(to: NSPoint(x: 25, y: 43))
        d.appendArc(withCenter: NSPoint(x: 25, y: 41), radius: 2, startAngle: 90, endAngle: 180, clockwise: false)
        d.line(to: NSPoint(x: 23, y: 23))
        d.appendArc(withCenter: NSPoint(x: 25, y: 23), radius: 2, startAngle: 180, endAngle: 270, clockwise: false)
        d.close()
        return d
    }
}

/// The menubar icon and its menu: what's going on (with a progress bar), Search…, the window, Pause, Settings, Quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    var onSearch: () -> Void = {}
    var onOpenWindow: () -> Void = {}
    var onSettings: () -> Void = {}
    var onChooseFolders: () -> Void = {}
    var onPauseChanged: (Bool) -> Void = { _ in }
    var onCheckForUpdates: () -> Void = {}
    private var shownProgress: Double?
    private var shownPaused = false
    private var shownUpdate = false

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
        observeModel()
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.status
            _ = model.progress
            _ = model.updateAvailable
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshButton()
                self?.observeModel()
            }
        }
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let progress = model.progress.map { ($0 * 50).rounded() / 50 }   // redraw in 2% steps, not every file
        let paused = model.status.paused, update = model.updateAvailable != nil
        if progress != shownProgress || paused != shownPaused || update != shownUpdate || button.image == nil {
            button.image = StatusIcon.image(progress: progress, paused: paused, update: update)
            shownProgress = progress
            shownPaused = paused
            shownUpdate = update
        }
        button.toolTip = "DigUp — \(model.statusLine)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem()
        let view = NSHostingView(rootView: MenuStatusView(model: model))
        view.frame.size = view.fittingSize
        header.view = view
        menu.addItem(header)
        menu.addItem(.separator())
        if let version = model.updateAvailable {
            menu.addItem(ActionMenuItem(Localization.current.format("menu.updateVersion", fallback: "Update to DigUp %@…", version)) { [weak self] in self?.onCheckForUpdates() })
            menu.addItem(.separator())
        }

        if !model.hasFolders {
            menu.addItem(ActionMenuItem(Localization.current.text("menu.chooseFolders", fallback: "Choose Folders to Search…")) { [weak self] in self?.onChooseFolders() })
        }
        let search = ActionMenuItem(Localization.current.text("menu.search", fallback: "Search…")) { [weak self] in self?.onSearch() }
        if let hotkey = model.hotkey, let (key, modifiers) = hotkey.menuEquivalent {
            search.keyEquivalent = key
            search.keyEquivalentModifierMask = modifiers
        }
        menu.addItem(search)
        menu.addItem(ActionMenuItem(Localization.current.text("menu.open", fallback: "Open DigUp")) { [weak self] in self?.onOpenWindow() })
        if model.hasFolders {
            menu.addItem(.separator())
            let paused = model.status.paused
            menu.addItem(ActionMenuItem(paused ? Localization.current.text("menu.resume", fallback: "Resume Indexing") : Localization.current.text("menu.pause", fallback: "Pause Indexing"), id: paused ? .resumeIndexing : .pauseIndexing) { [weak self] in
                self?.onPauseChanged(!paused)
            })
        }
        switch model.download.phase {
        case .failed, .needed:
            menu.addItem(ActionMenuItem(Localization.current.text("menu.download", fallback: "Download the Model")) { [weak self] in self?.model.download.start() })
        default:
            break
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(Localization.current.text("menu.settings", fallback: "Settings…"), key: ",") { [weak self] in self?.onSettings() })
        if model.updateAvailable == nil {
            menu.addItem(ActionMenuItem(Localization.current.text("menu.updates", fallback: "Check for Updates…")) { [weak self] in self?.onCheckForUpdates() })
        }
        menu.addItem(ActionMenuItem(Localization.current.text("menu.quit", fallback: "Quit DigUp"), key: "q") { NSApp.terminate(nil) })
    }

    /// The menu as text, for the -debugMenu launch argument (menus can't be clicked from a script).
    func describeMenu() -> String {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu.items.map { item in
            if item.isSeparatorItem { return "—" }
            if item.view != nil { return "[\(model.statusLine)]" }
            return item.title + (item.isEnabled ? "" : " (disabled)")
        }.joined(separator: " | ")
    }

    /// Debug actions use stable identities, independent of the displayed language.
    func performItem(id: MenuActionID) {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        id.perform(in: menu)
    }

}

/// The top of the menu: the status line, a detail (where, or how long), and progress while there is some.
struct MenuStatusView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.statusLine)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let progress = model.progress {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(width: 280, alignment: .leading)
    }

    private var detail: String? {
        if model.download.isActive { return model.download.progressText }
        if case .failed(let message) = model.download.phase { return message }
        guard model.hasFolders else { return Localization.current.text("menu.noFolders", fallback: "Pick the folders it should search.") }
        let missing = Set(model.status.missingRoots), unreadable = Set(model.status.unreadableRoots)
        let names = model.settings.roots.map { root in
            root.lastPathComponent + (missing.contains(root.path) ? Localization.current.text("folder.disconnected.suffix", fallback: " (not connected)")
                                      : unreadable.contains(root.path) ? Localization.current.text("folder.noAccess.suffix", fallback: " (no access)") : "")
        }
        return Localization.current.format("menu.folderList", fallback: "In %@", names.joined(separator: ", "))
    }
}

/// Makes an NSMenuItem that runs a closure.
private final class MenuAction: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

func ActionMenuItem(_ title: String, key: String = "", id: MenuActionID? = nil, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
    item.identifier = id.map { NSUserInterfaceItemIdentifier($0.rawValue) }
    item.target = action
    item.representedObject = action  // `target` is weak; this keeps the action alive
    return item
}

/// Display text must never be used to address a menu command.
enum MenuActionID: String {
    case pauseIndexing, resumeIndexing

    func perform(in menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.identifier?.rawValue == rawValue }), item.isEnabled,
              let action = item.representedObject as? MenuAction else { return }
        action.run()
    }
}

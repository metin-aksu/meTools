import Cocoa
import FinderSync
import os.log

/// Combined Finder Sync extension:
///   - "Cut from Here" / "Paste Here" (move files via the context menu)
///   - "New Text File" (create an empty .txt in the right-clicked folder)
/// Each feature is toggled from the meTools app through the shared
/// app-group defaults.
class FinderSync: FIFinderSync {

    private static let log = OSLog(subsystem: "com.metinaksu.metools.FinderExtension", category: "FinderSync")
    private let pendingCutKey = "pendingCutPaths"

    override init() {
        super.init()
        // Watch the whole file system so the menu items appear everywhere.
        // Desktop/Documents and iCloud Drive are listed explicitly because Finder
        // treats iCloud-managed locations as separate domains that "/" alone
        // does not always cover.
        let home = FileManager.default.homeDirectoryForCurrentUser
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            home,
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
        ]
    }

    // MARK: - Feature toggles (shared with the main app)

    private var cutPasteEnabled: Bool {
        MTSettings.defaults.object(forKey: MTSettings.cutPasteMenu) as? Bool ?? true
    }

    private var newTextFileEnabled: Bool {
        MTSettings.defaults.object(forKey: MTSettings.newTextFile) as? Bool ?? true
    }

    // MARK: - Pending cut state

    private var pendingCutPaths: [String] {
        get { MTSettings.defaults.stringArray(forKey: pendingCutKey) ?? [] }
        set { MTSettings.defaults.set(newValue, forKey: pendingCutKey) }
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        switch menuKind {
        case .contextualMenuForItems:
            guard cutPasteEnabled else { break }

            let cutItem = NSMenuItem(
                title: NSLocalizedString("cut_here", comment: "Context menu item that marks the selected files to be moved"),
                action: #selector(cutHere(_:)),
                keyEquivalent: ""
            )
            cutItem.target = self
            cutItem.image = menuImage(symbol: "scissors")
            menu.addItem(cutItem)

            // When a single folder is selected, offer to paste into it without entering it.
            if !pendingCutPaths.isEmpty, selectedSingleFolder() != nil {
                let pasteItem = NSMenuItem(
                    title: NSLocalizedString("paste_here", comment: "Context menu item that moves the previously cut files into the current folder"),
                    action: #selector(pasteIntoSelectedFolder(_:)),
                    keyEquivalent: ""
                )
                pasteItem.target = self
                pasteItem.image = menuImage(symbol: "doc.on.clipboard")
                menu.addItem(pasteItem)
            }

        case .contextualMenuForContainer:
            if cutPasteEnabled, !pendingCutPaths.isEmpty {
                let pasteItem = NSMenuItem(
                    title: NSLocalizedString("paste_here", comment: "Context menu item that moves the previously cut files into the current folder"),
                    action: #selector(pasteHere(_:)),
                    keyEquivalent: ""
                )
                pasteItem.target = self
                pasteItem.image = menuImage(symbol: "doc.on.clipboard")
                menu.addItem(pasteItem)
            }

            if newTextFileEnabled {
                let newFileItem = NSMenuItem(
                    title: NSLocalizedString("new_text_file", comment: "Context menu item that creates a new empty text file"),
                    action: #selector(newTextFile(_:)),
                    keyEquivalent: ""
                )
                newFileItem.target = self
                newFileItem.image = menuImage(symbol: "doc.text")
                menu.addItem(newFileItem)
            }

        default:
            break
        }

        return menu
    }

    // MARK: - Cut / Paste actions

    @objc func cutHere(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        pendingCutPaths = urls.map(\.path)
        os_log("Cut %d item(s)", log: Self.log, urls.count)
    }

    @objc func pasteHere(_ sender: AnyObject?) {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        movePendingItems(to: target)
    }

    @objc func pasteIntoSelectedFolder(_ sender: AnyObject?) {
        guard let target = selectedSingleFolder() else { return }
        movePendingItems(to: target)
    }

    private func movePendingItems(to target: URL) {
        let fileManager = FileManager.default
        var failures = 0

        for path in pendingCutPaths {
            let source = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: source.path) else {
                failures += 1
                continue
            }

            // Refuse to move a folder into itself or one of its own subfolders.
            if target.path == source.path || (target.path + "/").hasPrefix(source.path + "/") {
                failures += 1
                os_log("Skipped moving %{public}@ into itself", log: Self.log, type: .error, source.path)
                continue
            }

            let destination = uniqueDestination(for: source, in: target)

            // Moving onto itself (paste into the same folder) is a no-op.
            if destination.deletingLastPathComponent().path == source.deletingLastPathComponent().path,
               destination.lastPathComponent == source.lastPathComponent {
                continue
            }

            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                failures += 1
                os_log("Move failed for %{public}@: %{public}@", log: Self.log, type: .error, source.path, error.localizedDescription)
            }
        }

        pendingCutPaths = []

        if failures > 0 {
            NSSound.beep()
        }
    }

    /// The selected item, if the selection is exactly one folder.
    private func selectedSingleFolder() -> URL? {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              urls.count == 1,
              let url = urls.first else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        // Treat packages (.app bundles etc.) as files, not paste targets.
        if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            return nil
        }

        return url
    }

    // MARK: - New Text File action

    @objc func newTextFile(_ sender: AnyObject?) {
        // The folder whose background was right-clicked.
        guard let targetURL = FIFinderSyncController.default().targetedURL() else {
            os_log("newTextFile: targetedURL() was nil", log: Self.log, type: .error)
            return
        }

        let destination = uniqueDestination(in: targetURL, baseName: "untitled", ext: "txt")
        do {
            try Data().write(to: destination, options: .withoutOverwriting)
        } catch {
            os_log("newTextFile: could not create %{public}@: %{public}@",
                   log: Self.log, type: .error, destination.path, error.localizedDescription)
        }
    }

    // MARK: - Menu images

    /// Finder drops the template flag when menu images cross the extension boundary,
    /// so pre-tint the symbol to match the current light/dark appearance.
    private func menuImage(symbol: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let color: NSColor = menusAreDark ? .white : .black

        let pointSize = NSSize(width: 16, height: 16)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: pointSize)
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }

    /// Reads the current user's global "AppleInterfaceStyle" fresh (so it reflects
    /// a live Light/Dark toggle even in this long-lived extension process).
    private var menusAreDark: Bool {
        let value = CFPreferencesCopyValue("AppleInterfaceStyle" as CFString,
                                           kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser,
                                           kCFPreferencesAnyHost) as? String
        return value?.lowercased() == "dark"
    }

    // MARK: - Helpers

    /// Returns a destination URL inside `folder`, appending " 2", " 3", … if the name is taken.
    private func uniqueDestination(for source: URL, in folder: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = folder.appendingPathComponent(source.lastPathComponent)

        // Pasting back into the source folder should be treated as a no-op, not renamed.
        if candidate.path == source.path {
            return candidate
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }

    /// Returns a non-colliding URL inside `directory`:
    /// `untitled.txt`, then `untitled 2.txt`, `untitled 3.txt`, … (never overwrites).
    private func uniqueDestination(in directory: URL, baseName: String, ext: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(index).\(ext)")
            index += 1
        }
        return candidate
    }
}

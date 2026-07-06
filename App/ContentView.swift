import SwiftUI

struct ContentView: View {
    // Finder context-menu features.
    @AppStorage(MTSettings.cutPasteMenu, store: MTSettings.defaults) private var cutPasteMenu = true
    @AppStorage(MTSettings.newTextFile, store: MTSettings.defaults) private var newTextFile = true

    // Keyboard features.
    @AppStorage(MTSettings.returnOpens, store: MTSettings.defaults) private var returnOpens = true
    @AppStorage(MTSettings.f2Rename, store: MTSettings.defaults) private var f2Rename = true
    @AppStorage(MTSettings.ctrlCCopies, store: MTSettings.defaults) private var ctrlCCopies = true
    @AppStorage(MTSettings.ctrlVPastes, store: MTSettings.defaults) private var ctrlVPastes = true
    @AppStorage(MTSettings.ctrlXCuts, store: MTSettings.defaults) private var ctrlXCuts = true
    @AppStorage(MTSettings.ctrlZUndoes, store: MTSettings.defaults) private var ctrlZUndoes = true
    @AppStorage(MTSettings.backspaceDeletes, store: MTSettings.defaults) private var backspaceDeletes = true

    private func toggle(_ key: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(key)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("meTools")
                        .font(.largeTitle.bold())
                    Text("app_description")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    toggle("feature.cutPasteMenu", isOn: $cutPasteMenu)
                    toggle("feature.newTextFile", isOn: $newTextFile)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("section.finderMenu", systemImage: "filemenu.and.cursorarrow")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    toggle("feature.returnOpens", isOn: $returnOpens)
                    toggle("feature.f2Rename", isOn: $f2Rename)
                    toggle("feature.ctrlCCopies", isOn: $ctrlCCopies)
                    toggle("feature.ctrlVPastes", isOn: $ctrlVPastes)
                    toggle("feature.ctrlXCuts", isOn: $ctrlXCuts)
                    toggle("feature.ctrlZUndoes", isOn: $ctrlZUndoes)
                    toggle("feature.backspaceDeletes", isOn: $backspaceDeletes)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("section.keyboard", systemImage: "keyboard")
            }

            Text("note.permissions")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button {
                    openExtensionSettings()
                } label: {
                    Text("open_extension_settings")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    openAccessibilitySettings()
                } label: {
                    Text("open_accessibility_settings")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 520)
    }

    private func openExtensionSettings() {
        let urls = [
            // macOS 13+ Extensions pane, filtered to Finder extensions.
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
}

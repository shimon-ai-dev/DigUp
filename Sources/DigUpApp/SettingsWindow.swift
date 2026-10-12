import AppKit
import DigUpKit
import Observation
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, folders, code, storage

    var title: String {
        switch self {
        case .general: Localization.current.text("settings.tab.general", fallback: "General")
        case .folders: Localization.current.text("settings.tab.folders", fallback: "Folders")
        case .code: Localization.current.text("kind.code", fallback: "Code")
        case .storage: Localization.current.text("settings.tab.storage", fallback: "Storage")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .folders: "folder"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .storage: "internaldrive"
        }
    }
}

/// Settings, the way Mac apps lay them out: a toolbar of tabs, and the window sized to each one. Folders is also where
/// the index shows how far along it is, folder by folder.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let state: SettingsState
    /// Folders → Add Folders…, a sheet on this window.
    let addSheet: AddFoldersController
    /// Code → Add Folders… (code search's folders), a sheet on this window.
    let codeSheet: AddFoldersController
    private unowned let app: AppController
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    init(app: AppController) {
        self.app = app
        state = SettingsState(app: app)
        addSheet = AddFoldersController(app: app)
        codeSheet = AddFoldersController(app: app, code: true)
        super.init()
        state.addFolders = { [weak self] in self?.addFolders() }
        state.addCodeFolders = { [weak self] in self?.addCodeFolders() }
        for sheet in [addSheet, codeSheet] {
            sheet.onAdded = { [weak self] in
                guard let self else { return }
                Task { await self.state.refresh() }
            }
        }
    }

    /// Opens Add Folders on the Folders tab.
    func addFolders() {
        addSheet.begin(on: window)
    }

    /// Opens the code folders' sheet on the Code tab.
    func addCodeFolders() {
        codeSheet.begin(on: window)
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(_ tab: SettingsTab = .general) {
        let window = self.window ?? makeWindow()
        tabs?.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        state.tab = tab
        Task { await state.refresh() }
        app.present(window)
    }

    var selectedTab: SettingsTab { state.tab }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        for tab in SettingsTab.allCases {
            let controller = NSHostingController(rootView: SettingsPane(tab: tab, state: state))
            controller.sizingOptions = .preferredContentSize
            controller.title = tab.title   // the window takes the selected tab's title
            let item = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.tabs = tabs
        self.window = window
        state.selectTab = { [weak self] tab in
            self?.tabs?.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        addSheet.end()
        codeSheet.end()
        window?.contentViewController = nil
        window = nil
        tabs = nil
        app.windowClosed()
    }

    func snapshot(to url: URL) throws {
        try Snapshot.write(window, to: url)
    }
}

@Observable
final class SettingsState {
    var tab = SettingsTab.general
    private(set) var summaries: [Engine.RootSummary]?
    private(set) var codeSummaries: [Engine.RootSummary] = []
    private(set) var indexSize: Int64 = 0
    private(set) var codeIndexSize: Int64 = 0
    var launchAtLogin = false
    var loginProblem: String?
    var checksForUpdates = false
    @ObservationIgnored let app: AppController
    @ObservationIgnored var selectTab: (SettingsTab) -> Void = { _ in }
    @ObservationIgnored var addFolders: () -> Void = {}
    @ObservationIgnored var addCodeFolders: () -> Void = {}

    init(app: AppController) {
        self.app = app
    }

    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var refreshPending = false

    var model: AppModel { app.model }

    func refresh() async {
        lastRefresh = Date()
        launchAtLogin = app.launchesAtLogin
        checksForUpdates = app.updates.automaticallyChecks
        indexSize = app.engine.indexSize
        codeIndexSize = app.engine.codeIndexSize
        codeSummaries = await app.engine.rootSummaries(code: true)
        summaries = await app.engine.rootSummaries()
    }

    /// The index changed: refresh the folder counts, at most every 2 s while files are being indexed.
    func statusChanged() {
        guard !refreshPending else { return }
        refreshPending = true
        let wait = max(0, 2 - Date().timeIntervalSince(lastRefresh))
        Task {
            try? await Task.sleep(for: .seconds(wait))
            refreshPending = false
            await refresh()
        }
    }

    /// Ready to be drawn (debug snapshots wait for this).
    var isLoaded: Bool { summaries != nil }
}

/// One tab's content, at the width every tab shares.
private struct SettingsPane: View {
    let tab: SettingsTab
    let state: SettingsState

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettings(state: state)
            case .folders: FolderSettings(state: state)
            case .code: CodeSettings(state: state)
            case .storage: StorageSettings(state: state)
            }
        }
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Bindable var state: SettingsState

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ShortcutRecorder(combo: state.model.hotkey, apply: { state.app.setHotkey($0) },
                                     listening: { state.app.hotkeyRecording($0) }, capSize: 13)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.current.text("settings.shortcut.title", fallback: "Search shortcut"))
                        Text(Localization.current.text("settings.shortcut.detail", fallback: "Opens the search panel from any app."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { on in
                    state.loginProblem = state.app.setLaunchAtLogin(on)
                    state.launchAtLogin = state.app.launchesAtLogin
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.current.text("settings.login.title", fallback: "Open DigUp when you log in"))
                        Text(state.loginProblem ?? Localization.current.text("settings.login.detail", fallback: "So the shortcut always works."))
                            .font(.system(size: 11))
                            .foregroundStyle(state.loginProblem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { state.checksForUpdates }, set: { on in
                    state.app.updates.automaticallyChecks = on
                    state.checksForUpdates = on
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.current.text("settings.update.auto", fallback: "Check for updates automatically"))
                        Text(Localization.current.text("settings.update.detail", fallback: "Once a day DigUp asks GitHub for its newest version; nothing about your files is sent. Updates install with one click."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent {
                    Button(Localization.current.text("settings.update.now", fallback: "Check Now")) { state.app.updates.checkNow() }
                } label: {
                    Text(state.model.updateAvailable.map { Localization.current.format("update.available", fallback: "DigUp %@ is available", $0) }
                         ?? "DigUp \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct FolderSettings: View {
    @Bindable var state: SettingsState
    @State private var removing: Engine.RootSummary?

    var body: some View {
        Form {
            Section {
                IndexProgress(model: state.model) { state.app.engine.setPaused(!state.model.status.paused) }
            }
            Section {
                if let summaries = state.summaries {
                    if summaries.isEmpty {
                        Text(Localization.current.text("settings.folders.empty", fallback: "No folders yet. Add the ones DigUp should search."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(summaries) { summary in
                        FolderStatusRow(summary: summary) { removing = summary }
                    }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
            } header: {
                Text(Localization.current.text("settings.folders.title", fallback: "Folders to search"))
            } footer: {
                HStack {
                    Button(action: state.addFolders) {
                        Label(Localization.current.text("common.addFolders", fallback: "Add Folders…"), systemImage: "plus")
                    }
                    Spacer()
                }
            }
            Section {
                ForEach(state.model.settings.excludedFolders, id: \.path) { folder in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(tildePath(folder.path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            state.app.setExcluded(state.model.settings.excludedFolders.filter { $0 != folder })
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(Localization.current.text("settings.folders.searchAgain", fallback: "Search this folder again"))
                    }
                }
                if state.model.settings.excludedFolders.isEmpty {
                    Text(Localization.current.text("settings.exclusions.empty", fallback: "None. Code projects, app bundles and caches are skipped anyway (code has its own tab)."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(Localization.current.text("settings.exclusions.folders", fallback: "Skip these folders"))
            } footer: {
                HStack {
                    Button {
                        state.app.pickFolders(for: NSApp.keyWindow, prompt: Localization.current.text("common.skip", fallback: "Skip")) { folders in
                            guard !folders.isEmpty else { return }
                            state.app.setExcluded(state.model.settings.excludedFolders
                                + folders.filter { !state.model.settings.excludedFolders.contains($0) })
                        }
                    } label: {
                        Label(Localization.current.text("settings.exclusions.addFolder", fallback: "Skip a Folder…"), systemImage: "plus")
                    }
                    Spacer()
                }
            }
            Section {
                TypeExclusions(types: state.model.settings.excludedTypes) { state.app.setExcludedTypes($0) }
            } header: {
                Text(Localization.current.text("settings.exclusions.types", fallback: "Skip these file types"))
            } footer: {
                Text(Localization.current.text("settings.types.detail", fallback: "DigUp only reads pictures, PDFs, documents (txt, md, rtf, docx, odt, html), audio and video here; code is read only in the code folders (the Code tab). Keys, certificates and password files are never read, nor are hidden folders like ~/.ssh."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle(isOn: Binding(get: { state.model.settings.indexOnBattery },
                                     set: { state.app.setIndexOnBattery($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppSettings.batteryTitle)
                        Text(AppSettings.batteryDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onChange(of: state.model.status) { state.statusChanged() }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { removing != nil },
                                                               set: { if !$0 { removing = nil } })) {
            Button(Localization.current.text("common.remove", fallback: "Remove"), role: .destructive) {
                guard let removing else { return }
                state.app.removeFolder(URL(fileURLWithPath: removing.path))
                Task { await state.refresh() }
            }
        } message: {
            Text(Localization.current.format("settings.remove.explanation", fallback: "Removing this folder removes %@ from the index. Adding it back later indexes them again.", Localization.current.filesCount(removing?.files ?? 0)))
        }
    }

    private var removalTitle: String {
        Localization.current.format("settings.remove.title", fallback: "Stop searching “%@”?", removing.map { ($0.path as NSString).lastPathComponent } ?? "")
    }
}

/// Extensions typed as "heic, txt": applied on Return or when the field loses focus.
private struct TypeExclusions: View {
    let types: [String]
    let apply: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(Localization.current.text("settings.extensions.title", fallback: "Extensions"), text: $text, prompt: Text(Localization.current.text("settings.extensions.example", fallback: "e.g. heic, txt")))
            .labelsHidden()
            .focused($focused)
            .onSubmit { apply(text) }
            .onChange(of: focused) { _, now in if !now { apply(text) } }
            .onAppear { text = types.joined(separator: ", ") }
            .onChange(of: types) { _, now in text = now.joined(separator: ", ") }
    }
}

/// What the index is doing, with Pause/Resume.
private struct IndexProgress: View {
    let model: AppModel
    let togglePause: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.statusLine).font(.system(size: 13, weight: .semibold))
                if let progress = model.progress {
                    ProgressView(value: progress).controlSize(.small)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasFolders {
                Button(model.status.paused ? Localization.current.text("common.resume", fallback: "Resume") : Localization.current.text("common.pause", fallback: "Pause"), action: togglePause)
            }
        }
    }

    /// "357 of 365 files searchable · 8 waiting · 2 long files to finish"
    private var detail: String {
        let status = model.status
        var parts = [Localization.current.format("settings.index.searchable", fallback: "%lld of %lld files searchable", Int64(status.searchable), Int64(status.files))]
        if status.pending > 0 { parts.append(Localization.current.format("settings.index.waiting", fallback: "%lld waiting", Int64(status.pending))) }
        if status.unfinished > 0 { parts.append(Localization.current.count("count.longRemaining", status.unfinished, one: "%lld long file to finish", other: "%lld long files to finish")) }
        if model.download.isActive { parts.append(Localization.current.format("settings.index.model", fallback: "model %@", model.download.progressText)) }
        return parts.joined(separator: " · ")
    }
}

private struct FolderStatusRow: View {
    let summary: Engine.RootSummary
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: summary.missing ? "/Volumes" : summary.path))
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(summary.missing ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text((summary.path as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold))
                    if summary.missing || summary.unreadable {
                        Text(summary.missing ? Localization.current.text("folder.disconnected", fallback: "Not connected") : Localization.current.text("folder.noAccess", fallback: "No access"))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                    }
                    if summary.unreadable {
                        Button(Localization.current.text("folder.allowSettings", fallback: "Allow in Settings…"), action: openFolderPrivacySettings)
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
                Text(tildePath(summary.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !summary.kinds.isEmpty {
                    KindCounts(counts: summary.kinds).padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.missing || summary.unreadable ? Localization.current.text("folder.kept", fallback: "Kept for when it's back")
                     : Localization.current.format("settings.folder.indexed", fallback: "%lld of %lld indexed", Int64(summary.indexed), Int64(summary.files)))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                if !states.isEmpty {
                    Text(states).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Localization.current.text("folder.stopSearching", fallback: "Stop searching this folder"))
            .accessibilityLabel(Localization.current.format("settings.folder.remove.accessibility", fallback: "Remove %@", (summary.path as NSString).lastPathComponent))
        }
        .padding(.vertical, 2)
    }

    private var states: String {
        [summary.pending > 0 ? Localization.current.format("settings.index.waiting", fallback: "%lld waiting", Int64(summary.pending)) : nil,
         summary.unfinished > 0
            ? Localization.current.count("count.longRemaining", summary.unfinished, one: "%lld long file to finish", other: "%lld long files to finish") : nil,
         summary.skipped > 0 ? Localization.current.format("settings.index.skipped", fallback: "%lld skipped", Int64(summary.skipped)) : nil,
         summary.failed > 0 ? Localization.current.format("settings.index.failed", fallback: "%lld couldn't be read", Int64(summary.failed)) : nil].compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct StorageSettings: View {
    let state: SettingsState

    var body: some View {
        Form {
            Section(Localization.current.text("storage.model", fallback: "Model")) {
                LabeledContent("EmbeddingGemma 2") {
                    Text("Google · Apache 2.0 · 865 MB")
                }
                LabeledContent(Localization.current.text("storage.status", fallback: "Status")) {
                    HStack(spacing: 8) {
                        Text(state.model.download.isReady ? Localization.current.text("storage.downloaded", fallback: "Downloaded") : state.model.download.progressText)
                        switch state.model.download.phase {
                        case .needed, .failed:
                            Button(Localization.current.text("common.download", fallback: "Download")) { state.model.download.start() }.controlSize(.small)
                        default:
                            EmptyView()
                        }
                    }
                }
                LabeledContent(Localization.current.text("storage.location", fallback: "Location")) {
                    PathButton(url: state.model.settings.modelsDirectory)
                }
            }
            Section(Localization.current.text("storage.index", fallback: "Index")) {
                LabeledContent(Localization.current.text("storage.size", fallback: "Size on disk"), value: bytes(state.indexSize))
                if state.model.hasCode {
                    LabeledContent(Localization.current.text("storage.codeIndex", fallback: "Code index"), value: bytes(state.codeIndexSize))
                }
                LabeledContent(Localization.current.text("storage.location", fallback: "Location")) {
                    PathButton(url: state.model.settings.indexDirectory)
                }
            }
            Section(Localization.current.text("storage.privacy", fallback: "Privacy")) {
                Text(Localization.current.text("storage.privacy.detail", fallback: "DigUp reads the folders you choose and keeps what it learns in its index, on this Mac. It goes online only to download its model, once, and to check for updates (General), which sends nothing about your files."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text(Localization.current.format("storage.credits", fallback: "DigUp %@ · EmbeddingGemma 2 by Google (Apache 2.0), run by llama.cpp (MIT).", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

/// Code search: its folders and how far along their index is, the editor results open in, and turning it off.
private struct CodeSettings: View {
    @Bindable var state: SettingsState
    @State private var turningOff = false
    @State private var removing: Engine.RootSummary?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Localization.current.text("code.search.title", fallback: "Search your code")).font(.system(size: 13, weight: .semibold))
                    Text(Localization.current.text("settings.code.description", fallback: "Find code by what it does, or by a name in it: type code: in the search panel, as in “code: retry with backoff”. Code has an index of its own, and it never shows up in other searches."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state.model.hasCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(state.model.codeStatusLine).font(.system(size: 12, weight: .medium))
                            if let indexing = state.model.status.code.indexing, indexing.total > 0 {
                                ProgressView(value: Double(indexing.done) / Double(indexing.total)).controlSize(.small)
                            }
                        }
                        Spacer()
                        Text(bytes(state.codeIndexSize))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if state.codeSummaries.isEmpty {
                    Text(Localization.current.text("code.folders.empty", fallback: "No code folders yet. Add the folders that hold your projects."))
                        .foregroundStyle(.secondary)
                }
                ForEach(state.codeSummaries) { summary in
                    FolderStatusRow(summary: summary) { removing = summary }
                }
            } header: {
                Text(Localization.current.text("code.folders.title", fallback: "Code folders"))
            } footer: {
                HStack {
                    Button(action: state.addCodeFolders) {
                        Label(state.model.hasCode ? Localization.current.text("common.addFolders", fallback: "Add Folders…") : Localization.current.text("code.chooseFolders", fallback: "Choose Code Folders…"), systemImage: "plus")
                    }
                    Spacer()
                }
            }
            Section {
                Picker(Localization.current.text("code.openIn", fallback: "Open code in"), selection: Binding(get: { CodeEditor.current.id },
                                                          set: { state.app.setCodeEditor($0) })) {
                    ForEach(CodeEditor.installed) { editor in Text(editor.name).tag(editor.id) }
                    Text(CodeEditor.defaultApp.name).tag(CodeEditor.defaultApp.id)
                }
            } footer: {
                Text(Localization.current.text("code.open.detail", fallback: "A result opens there at the line that matched. Space shows the whole file in Quick Look."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(Localization.current.text("settings.code.privacy", fallback: "The code index keeps your code's text on this Mac, as the main index keeps your documents'. It skips what git ignores, vendored and generated code, data files, and anything that looks like a key or a password."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state.model.hasCode {
                    HStack {
                        Spacer()
                        Button(Localization.current.text("code.disable.button", fallback: "Turn Off Code Search…"), role: .destructive) { turningOff = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onChange(of: state.model.status) { state.statusChanged() }
        .confirmationDialog(Localization.current.text("code.disable.confirm", fallback: "Turn off code search?"), isPresented: $turningOff) {
            Button(Localization.current.text("code.disable.action", fallback: "Turn Off"), role: .destructive) {
                state.app.applyCodeFolders([], excluded: [])
                Task { await state.refresh() }
            }
        } message: {
            Text(Localization.current.format("settings.code.deleteExplanation", fallback: "The code index (%@) is deleted. Turning it on again reads the code again.", bytes(state.codeIndexSize)))
        }
        .confirmationDialog(Localization.current.format("settings.code.removeTitle", fallback: "Stop searching the code in “%@”?", removing.map { ($0.path as NSString).lastPathComponent } ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(Localization.current.text("common.remove", fallback: "Remove"), role: .destructive) {
                guard let removing else { return }
                state.app.removeCodeFolder(URL(fileURLWithPath: removing.path))
                Task { await state.refresh() }
            }
        } message: {
            Text(Localization.current.format("settings.code.removeExplanation", fallback: "This removes %@ from the code index.", Localization.current.count("count.kind.code", removing?.files ?? 0, one: "%lld code file", other: "%lld code files")))
        }
    }
}

/// "~/Library/…/Models" that shows the folder in Finder.
private struct PathButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            HStack(spacing: 4) {
                Text(tildePath(url.path)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(Localization.current.text("common.reveal", fallback: "Show in Finder"))
    }
}

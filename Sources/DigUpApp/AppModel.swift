import AppKit
import Observation

/// State the menubar, the panel and the windows share. Engine updates arrive on the main thread.
@Observable
final class AppModel {
    var status = EngineStatus()
    var settings: AppSettings
    var hotkey: KeyCombo?
    let download: ModelDownload
    /// A newer DigUp the daily check found ("0.6.1"), until you open it (`Updates`).
    var updateAvailable: String?

    init(settings: AppSettings, download: ModelDownload) {
        self.settings = settings
        self.download = download
    }

    var hasFolders: Bool { !settings.roots.isEmpty }
    /// Code search is on (there are code folders).
    var hasCode: Bool { !settings.codeRoots.isEmpty }

    /// One line for the menu and the windows: what the index is doing.
    var statusLine: String {
        let l = Localization.current
        let status = self.status
        guard hasFolders else { return l.text("search.noFolders", fallback: "No folders chosen yet") }
        switch status.activity {
        case .starting: return l.text("status.starting", fallback: "Starting…")
        case .failed(let problem): return "⚠︎ \(problem)"
        case .syncing: return l.text("status.checking", fallback: "Checking folders…")
        case .indexing(let done, let total): return l.indexingProgress(done: done, total: total)
        case .finishing(let done, let total, let files):
            let which = files > 0 ? l.count("count.longFiles", files, one: "%lld long file", other: "%lld long files") : l.text("status.longFiles", fallback: "long files")
            return l.format("status.finishing", fallback: "Reading the rest of %@ · %@", which, l.percent(total > 0 ? Double(done) / Double(total) : 0))
        case .idle:
            if let line = downloadLine { return line }
            if let code = status.code.indexing, code.total > 0 { return l.indexingCodeProgress(done: code.done, total: code.total) }
            if status.pending > 0 {
                if status.paused { return l.format("status.pausedDetail", fallback: "Paused · %@", l.waitingFiles(status.pending, reason: nil)) }
                return l.waitingFiles(status.pending, reason: status.waitingFor)
            }
            if status.unfinished > 0 {
                let rest = l.count("count.longRemaining", status.unfinished, one: "%lld long file to finish", other: "%lld long files to finish")
                if status.paused { return l.format("status.pausedDetail", fallback: "Paused · %@", rest) }
                if let reason = status.waitingFor { return l.format("status.waiting.reason", fallback: "%@ · %@", rest, reason) }
            }
            let indexed = l.count("count.indexed", status.searchable, one: "%lld file indexed", other: "%lld files indexed")
            return status.paused ? l.format("status.indexedPaused", fallback: "%@ · paused", indexed) : indexed
        }
    }

    /// While the model isn't there, how its download goes.
    private var downloadLine: String? {
        let l = Localization.current
        switch download.phase {
        case .ready: return nil
        case .downloading: return l.format("status.downloading", fallback: "Downloading the model · %@", l.percent(download.fraction))
        case .verifying: return l.text("status.download.verifying", fallback: "Checking the model download…")
        case .retrying: return l.text("status.download.retry", fallback: "Model download: waiting for the network")
        case .failed: return l.text("status.download.stopped", fallback: "⚠︎ The model download stopped")
        case .needed: return status.pending > 0 ? l.text("status.download.needed", fallback: "The model isn't downloaded yet") : nil
        }
    }

    /// 0…1 for the menubar ring and progress bars: the model download, then an indexing pass or the rest of long files.
    var progress: Double? {
        if download.isActive { return download.fraction }
        switch status.activity {
        case .indexing(let done, let total) where total > 0: return Double(done) / Double(total)
        case .finishing(let done, let total, _) where total > 0: return Double(done) / Double(total)
        case .idle:
            guard let code = status.code.indexing, code.total > 0 else { return nil }
            return Double(code.done) / Double(code.total)
        default: return nil
        }
    }

    /// One line about the code index, for Settings → Code: "812 code files indexed", "Indexing code 42%…".
    var codeStatusLine: String {
        let l = Localization.current
        let code = status.code
        guard hasCode else { return l.text("search.code.off", fallback: "Code search is off") }
        if !download.isReady { return l.text("status.code.waitModel", fallback: "Code is read once the model has downloaded") }
        if let indexing = code.indexing, indexing.total > 0 { return l.indexingCodeProgress(done: indexing.done, total: indexing.total) }
        let waiting = l.count("count.codeWaiting", code.pending, one: "%lld code file waiting", other: "%lld code files waiting")
        if code.pending > 0, status.paused { return l.format("status.pausedDetail", fallback: "Paused · %@", waiting) }
        if code.pending > 0, let reason = status.waitingFor { return l.format("status.waiting.reason", fallback: "%@ · %@", waiting, reason) }
        let indexed = l.count("count.codeIndexed", code.searchable, one: "%lld code file indexed", other: "%lld code files indexed")
        return code.pending > 0 ? l.format("status.code.indexedWaiting", fallback: "%@ · %@", indexed, waiting) : indexed
    }

    /// A few words for the search bar while results may be incomplete: "Indexing 42%", "Downloading model · 42%".
    var activityBadge: String? {
        let l = Localization.current
        if download.isActive { return l.format("status.badge.downloading", fallback: "Downloading model · %@", l.percent(download.fraction)) }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return l.format("status.badge.indexing", fallback: "Indexing %@", l.percent(Double(done) / Double(total)))
        }
        if status.paused, status.pending > 0 { return l.text("status.badge.paused", fallback: "Indexing paused") }
        return nil
    }

    /// Why meaning search can't run yet (words still match), or nil.
    var meaningUnavailable: String? {
        let l = Localization.current
        guard !download.isReady else { return nil }
        if download.isActive { return l.format("status.meaning.downloading", fallback: "Matching words only until the model has downloaded (%@)", l.percent(download.fraction)) }
        return l.text("status.meaning.missing", fallback: "Matching words only: the model isn't downloaded")
    }

    /// Why results may be incomplete right now, or nil.
    var resultsCaveat: String? {
        let l = Localization.current
        if let meaningUnavailable { return meaningUnavailable }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return l.format("status.results.incomplete", fallback: "Still indexing (%@): some files aren't in yet", l.percent(Double(done) / Double(total)))
        }
        if status.pending > 0 { return l.count("count.notIndexed", status.pending, one: "%lld file isn't indexed yet", other: "%lld files aren't indexed yet") }
        return nil
    }
}

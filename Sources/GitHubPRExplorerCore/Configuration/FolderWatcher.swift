import Foundation

/// Watches the configuration folder and calls `onChange` shortly after anything in it changes,
/// so an edit made by an agent or an editor shows in the running app without a relaunch.
///
/// It watches the folder, each folder inside it, and each file in those, with a dispatch
/// source per item, after `mac-os-agent`'s `FolderWatcher`. Watching the folders sees a file
/// that is added, removed, or replaced by a rename, which is how most editors save. Watching
/// the files as well sees a file written in place, as a shell's `>` does. Hidden items, such as
/// `.git`, are not watched, so recording a version does not set it off.
///
/// When the folder does not exist yet, it watches nothing until `rearm()` finds it.
@MainActor
public final class FolderWatcher {
    public let folder: URL
    private let delay: Duration
    private let onChange: @MainActor () -> Void
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: Task<Void, Never>?

    /// - Parameter delay: How long to wait after a change before calling `onChange`, so a burst
    ///   of writes, such as an atomic save's temporary file and rename, is one call.
    public init(folder: URL, delay: Duration = .milliseconds(250), onChange: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.delay = delay
        self.onChange = onChange
        rearm()
    }

    isolated deinit {
        pending?.cancel()
        for source in sources.values { source.cancel() }
    }

    /// True while the folder itself is watched.
    public var isWatching: Bool { sources[folder.path] != nil }

    /// Watches the folder and what is in it as it is now. Called after every change, so a new
    /// file is watched from then on and a removed one lets go.
    public func rearm() {
        var wanted = [folder]
        var folders = [folder]
        while let current = folders.popLast() {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: current, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for item in contents {
                wanted.append(item)
                // One level of folders is enough: the configuration has `layouts/` and no deeper.
                if current == folder, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    folders.append(item)
                }
            }
        }
        let paths = Set(wanted.map(\.path))
        for (path, source) in sources where !paths.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for url in wanted where sources[url.path] == nil {
            watch(url)
        }
    }

    private func watch(_ url: URL) {
        let path = url.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    // The item went away or was replaced. Watch it again if it comes back.
                    source.cancel()
                    if self.sources[path] === source { self.sources[path] = nil }
                }
                self.scheduleChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources[path] = source
    }

    private func scheduleChange() {
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.rearm()
            self.onChange()
        }
    }
}

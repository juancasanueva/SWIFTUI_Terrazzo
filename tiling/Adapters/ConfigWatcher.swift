import Foundation

/// Calls back when anything in the config directory changes. The directory source sees atomic saves,
/// which replace a file; the per-file sources see editors and shells that write in place.
final class ConfigWatcher {
    private var directory: URL?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    var onChange: (() -> Void)?

    func start(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        rearm()
    }

    private func rearm() {
        sources.forEach { $0.cancel() }
        sources = []
        guard let directory else { return }
        watch(directory.path)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".json") {
            watch(directory.appendingPathComponent(file).path)
        }
    }

    private func watch(_ path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rearm()
            self?.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

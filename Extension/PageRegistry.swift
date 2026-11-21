import SafariServices

/// Remembers which pages have videos (to enable the toolbar button) and which page
/// currently owns the floating video (so global controls reach it from any tab).
/// Lives as long as the extension process; when Safari restarts the process the
/// registry starts empty and fills again as pages report in.
final class PageRegistry {
    static let shared = PageRegistry()
    private let lock = NSLock()
    private var videoPages: [(page: SFSafariPage, found: Bool)] = []
    private(set) var pipPage: SFSafariPage?

    func setHasVideo(_ found: Bool, for page: SFSafariPage) {
        lock.lock(); defer { lock.unlock() }
        videoPages.removeAll { $0.page.isEqual(page) }
        videoPages.append((page, found))
        if videoPages.count > 300 { videoPages.removeFirst(videoPages.count - 300) }
    }

    func hasVideo(_ page: SFSafariPage) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return videoPages.last { $0.page.isEqual(page) }?.found ?? false
    }

    func setPiP(_ active: Bool, page: SFSafariPage) {
        lock.lock(); defer { lock.unlock() }
        if active {
            pipPage = page
        } else if let current = pipPage, current.isEqual(page) {
            pipPage = nil
        }
    }

    func isPiP(_ page: SFSafariPage) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pipPage?.isEqual(page) ?? false
    }
}

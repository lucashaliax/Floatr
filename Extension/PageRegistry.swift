import SafariServices

/// Remembers which page currently owns the floating video, so global controls reach it from
/// any tab. Lives as long as the extension process: Safari quits idle extensions and starts
/// them again on demand, so this state can disappear at any time and must never be required.
final class PageRegistry {
    static let shared = PageRegistry()
    private let lock = NSLock()
    private(set) var pipPage: SFSafariPage?

    func setPiP(_ active: Bool, page: SFSafariPage) {
        lock.lock(); defer { lock.unlock() }
        if active {
            pipPage = page
        } else if let current = pipPage, current.isEqual(page) {
            pipPage = nil
        }
    }

    /// Forget the floating page (it closed, reloaded or navigated without telling us).
    func clearPiP(ifStill page: SFSafariPage) {
        lock.lock(); defer { lock.unlock() }
        if let current = pipPage, current.isEqual(page) { pipPage = nil }
    }

    func isPiP(_ page: SFSafariPage) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pipPage?.isEqual(page) ?? false
    }
}

/// Sends commands to pages and notices when nobody answers.
///
/// A page answers every command with "ack" right away. No answer means the page is gone, or
/// it has no content script (opened before Floatr was installed or updated, or the site isn't
/// allowed in Safari's settings). Without this, such commands were lost silently.
final class CommandTracker {
    static let shared = CommandTracker()
    static let timeout: TimeInterval = 1.0

    private let lock = NSLock()
    private var pending: [String: DispatchWorkItem] = [:]

    func send(_ name: String, to page: SFSafariPage, userInfo: [String: Any] = [:],
              onNoAnswer: @escaping () -> Void) {
        let id = UUID().uuidString
        var info = userInfo
        info["id"] = id
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.take(id) else { return }
            onNoAnswer()
        }
        lock.lock(); pending[id] = work; lock.unlock()
        page.dispatchMessageToScript(withName: name, userInfo: info)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: work)
    }

    func ack(_ id: String) {
        take(id)
    }

    /// Removes a pending command; true if it was still waiting.
    @discardableResult
    private func take(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let work = pending.removeValue(forKey: id) else { return false }
        work.cancel()
        return true
    }
}

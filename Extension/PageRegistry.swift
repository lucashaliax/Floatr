import SafariServices
import os

private let probeLog = Logger(subsystem: Floatr.extensionBundleID, category: "probe")

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

/// Asks every open tab what video it has, to send the shortcut to the tab the user is
/// listening to when the front tab has nothing playing.
final class TabProbe {
    struct Answer {
        let score: Double
        let playing: Bool
        let audible: Bool
        var hasVideo: Bool { score >= 0 }
    }

    static let shared = TabProbe()
    static let timeout: TimeInterval = 0.4

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    private final class Session {
        let pages: [SFSafariPage]
        let front: SFSafariPage?
        var answers: [Int: Answer] = [:]
        var finished = false
        let completion: (SFSafariPage?) -> Void
        init(pages: [SFSafariPage], front: SFSafariPage?, completion: @escaping (SFSafariPage?) -> Void) {
            self.pages = pages; self.front = front; self.completion = completion
        }
    }

    /// Picks the page for a command: the front tab if its video is playing; else a tab playing
    /// audio; else the front tab if it has any video; else the front tab (which then reports
    /// "No video in this tab"). Pages are in window order, front window first.
    func choose(front: SFSafariPage?, pages: [SFSafariPage], completion: @escaping (SFSafariPage?) -> Void) {
        guard !pages.isEmpty else { return completion(front) }
        let session = Session(pages: pages, front: front, completion: completion)
        var ids: [String] = []
        lock.lock()
        for i in pages.indices {
            let id = "\(UUID().uuidString)#\(i)"
            sessions[id] = session
            ids.append(id)
        }
        lock.unlock()
        for (i, page) in pages.enumerated() {
            page.dispatchMessageToScript(withName: "probe", userInfo: ["id": ids[i]])
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            self?.finish(session, ids: ids)
        }
    }

    func receive(id: String, info: [String: Any]) {
        lock.lock()
        guard let session = sessions[id], !session.finished,
              let index = id.split(separator: "#").last.flatMap({ Int($0) }) else { lock.unlock(); return }
        session.answers[index] = Answer(score: (info["score"] as? NSNumber)?.doubleValue ?? -1,
                                        playing: info["playing"] as? Bool ?? false,
                                        audible: info["audible"] as? Bool ?? false)
        let frontPlaying = session.front.flatMap { f in session.pages.firstIndex { $0.isEqual(f) } }
            .flatMap { session.answers[$0] }?.playing ?? false
        let all = session.answers.count == session.pages.count
        lock.unlock()
        // No need to wait for the others once the front tab is playing, or everyone answered.
        if frontPlaying || all { finish(session, ids: nil) }
    }

    private func finish(_ session: Session, ids: [String]?) {
        lock.lock()
        if session.finished { lock.unlock(); return }
        session.finished = true
        sessions = sessions.filter { $0.value !== session }
        let answers = session.answers
        lock.unlock()

        let pages = session.pages
        let frontIndex = session.front.flatMap { f in pages.firstIndex { $0.isEqual(f) } }
        let summary = pages.indices.map { i -> String in
            guard let a = answers[i] else { return "\(i):-" }
            return "\(i)\(i == frontIndex ? "*" : ""):\(a.hasVideo ? "v" : "")\(a.playing ? "p" : "")\(a.audible ? "a" : "")"
        }.joined(separator: " ")
        probeLog.info("probe \(answers.count)/\(pages.count) tabs answered [\(summary, privacy: .public)]")
        let front = frontIndex.flatMap { answers[$0] }
        let pick: SFSafariPage?
        if front?.playing == true {
            pick = session.front
        } else if let i = pages.indices.first(where: { $0 != frontIndex && answers[$0]?.audible == true }) {
            pick = pages[i]
        } else {
            pick = session.front
        }
        session.completion(pick)
    }
}

/// The page that asked for a click (PiP refused without a user gesture). The app then presses
/// the toolbar button, and that click must reach this page even if it's in a background tab.
final class GestureTarget {
    static let shared = GestureTarget()
    private let lock = NSLock()
    private var page: SFSafariPage?
    private var date = Date.distantPast

    func set(_ page: SFSafariPage) {
        lock.lock(); self.page = page; date = Date(); lock.unlock()
    }

    /// The waiting page, if it asked in the last 3 seconds; cleared once taken.
    func take() -> SFSafariPage? {
        lock.lock(); defer { lock.unlock() }
        defer { page = nil }
        return Date().timeIntervalSince(date) < 3 ? page : nil
    }
}

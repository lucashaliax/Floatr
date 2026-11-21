import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys through Carbon's `RegisterEventHotKey`.
/// Unlike an event tap, this needs no Accessibility or Input Monitoring permission.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onHotkey: ((PiPCommand) -> Void)?

    private let signature: OSType = 0x464C_5452 // 'FLTR'
    private var refs: [EventHotKeyRef] = []
    private var commandsByID: [UInt32: PiPCommand] = [:]
    private var handlerRef: EventHandlerRef?
    private var current: [PiPCommand: Shortcut] = [:]
    private(set) var isSuspended = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            if let cmd = center.commandsByID[hk.id] {
                DispatchQueue.main.async { center.onHotkey?(cmd) }
            }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    /// Registers the given shortcuts, replacing the previous set.
    /// Returns the commands whose shortcut is already taken by another app.
    @discardableResult
    func register(_ shortcuts: [PiPCommand: Shortcut]) -> Set<PiPCommand> {
        installHandlerIfNeeded()
        unregisterAll()
        current = shortcuts
        guard !isSuspended else { return [] }
        var failed = Set<PiPCommand>()
        for (index, cmd) in PiPCommand.allCases.enumerated() {
            guard let sc = shortcuts[cmd], sc.isValidGlobal else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(sc.keyCode, sc.modifiers, EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                commandsByID[id] = cmd
            } else {
                failed.insert(cmd)
            }
        }
        return failed
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        commandsByID.removeAll()
    }

    /// While the user records a new shortcut, existing ones must not fire.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        register(current)
    }
}

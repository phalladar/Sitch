import AppKit
import Carbon.HIToolbox
import SitchCore

/// Global hotkeys via Carbon RegisterEventHotKey (windows/Sitch/Shell/HotkeyManager.cs used
/// RegisterHotKey). Carbon hotkeys need no Accessibility permission, unlike an NSEvent global
/// monitor, and they swallow the keystroke so the frontmost app never sees it.
@MainActor
final class HotkeyManager {
    var onPressed: ((Int) -> Void)?

    private var registered: [Int: (ref: EventHotKeyRef, key: UInt32)] = [:]

    // One application-wide Carbon handler; hotkey ids route back to the owning manager.
    private static var handlerInstalled = false
    private static var routes: [UInt32: () -> Void] = [:]
    private static var nextKey: UInt32 = 1
    private static let signature: OSType = 0x5349_5443 // 'SITC'

    init() { Self.installHandler() }

    /// False if the combination is taken (or invalid).
    func register(id: Int, _ chord: HotkeyChord) -> Bool {
        unregister(id: id)
        guard let code = chord.keyCode else { return false }
        var mods: UInt32 = 0
        if chord.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }

        let key = Self.nextKey
        Self.nextKey += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(code), mods, EventHotKeyID(signature: Self.signature, id: key),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registered[id] = (ref, key)
        Self.routes[key] = { [weak self] in self?.onPressed?(id) }
        return true
    }

    func unregister(id: Int) {
        guard let entry = registered.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
        Self.routes[entry.key] = nil
    }

    func unregisterAll() {
        for id in Array(registered.keys) { unregister(id: id) }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Carbon delivers application-target events on the main thread.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr, hk.signature == HotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let key = hk.id
            MainActor.assumeIsolated { HotkeyManager.routes[key]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

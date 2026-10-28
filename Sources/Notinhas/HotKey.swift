import Carbon.HIToolbox

/// System-wide shortcut through Carbon's RegisterEventHotKey, which (unlike an
/// NSEvent global monitor) needs no Accessibility permission.
final class HotKey {
    private static var nextID: UInt32 = 1
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every HotKey's handler sees every hot key press: pass on the ones for another.
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E54_4E48), id: id) // "NTNH"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

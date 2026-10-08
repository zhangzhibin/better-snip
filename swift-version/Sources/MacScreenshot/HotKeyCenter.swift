import Carbon
import Cocoa

/// 用 Carbon 热键注册全局快捷键。不依赖辅助功能权限，且会吃掉按键，避免传给前台应用。
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var suspended = false
    private let signature: OSType = 0x4D534350 // 'MSCP'
    private let hotKeyID: UInt32 = 1

    private init() {
        installHandler()
        registerCurrent()
    }

    /// 录制新快捷键时先摘掉热键，避免按键被全局热键吃掉。
    func setSuspended(_ value: Bool) {
        suspended = value
        if value {
            unregister()
        } else {
            registerCurrent()
        }
    }

    func registerCurrent() {
        guard !suspended else { return }
        unregister()
        let hotKeyID = EventHotKeyID(signature: signature, id: self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(AppPreferences.hotkeyKeyCode),
            AppPreferences.carbonHotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("[HotKeyCenter] RegisterEventHotKey failed: %d", status)
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard id == hotKeyID, !suspended else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onPressed?()
        }
    }
}

private func carbonHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status != noErr { return status }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.handleHotKey(id: hotKeyID.id)
    return noErr
}

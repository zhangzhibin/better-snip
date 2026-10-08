import Carbon
import Cocoa

/// 确认截图时的默认去向。按住 Option 会在两者之间对调。
enum SaveDestination: String {
    case clipboard
    case file
}

enum AppPreferences {
    private static let keyCodeKey = "hotkeyKeyCode"
    private static let modifiersKey = "hotkeyModifiers"
    private static let characterKey = "hotkeyCharacter"
    private static let directoryKey = "saveDirectory"
    private static let destinationKey = "saveDestination"

    /// kVK_ANSI_C
    static let defaultKeyCode: UInt16 = 8
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .option]
    static let defaultCharacter = "c"

    static var hotkeyKeyCode: UInt16 {
        get {
            guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else { return defaultKeyCode }
            return UInt16(UserDefaults.standard.integer(forKey: keyCodeKey))
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: keyCodeKey) }
    }

    static var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            guard UserDefaults.standard.object(forKey: modifiersKey) != nil else { return defaultModifiers }
            return NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: modifiersKey)))
                .intersection([.command, .option, .shift, .control])
        }
        set {
            let cleaned = newValue.intersection([.command, .option, .shift, .control])
            UserDefaults.standard.set(Int(cleaned.rawValue), forKey: modifiersKey)
        }
    }

    /// 菜单和偏好设置里显示的按键字符（小写）
    static var hotkeyCharacter: String {
        get {
            let value = UserDefaults.standard.string(forKey: characterKey) ?? defaultCharacter
            return value.isEmpty ? defaultCharacter : value.lowercased()
        }
        set { UserDefaults.standard.set(newValue.lowercased(), forKey: characterKey) }
    }

    static var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: directoryKey), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: directoryKey) }
    }

    static var destination: SaveDestination {
        get { SaveDestination(rawValue: UserDefaults.standard.string(forKey: destinationKey) ?? "") ?? .clipboard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: destinationKey) }
    }

    static func resetHotkey() {
        hotkeyKeyCode = defaultKeyCode
        hotkeyModifiers = defaultModifiers
        hotkeyCharacter = defaultCharacter
    }

    static func shortcutDisplay(character: String = hotkeyCharacter, modifiers: NSEvent.ModifierFlags = hotkeyModifiers) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += character.uppercased()
        return text
    }

    /// Carbon RegisterEventHotKey 使用的修饰键掩码
    static var carbonHotkeyModifiers: UInt32 {
        var mask: UInt32 = 0
        let flags = hotkeyModifiers
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}

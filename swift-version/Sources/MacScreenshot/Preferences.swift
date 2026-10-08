import Carbon
import Cocoa

/// 确认截图时的默认去向。按住 Option 时，剪贴板与文件对调；两者都保存时不变。
enum SaveDestination: String {
    case clipboard
    case file
    case both

    func resolving(optionHeld: Bool) -> SaveDestination {
        guard optionHeld else { return self }
        switch self {
        case .clipboard: return .file
        case .file: return .clipboard
        case .both: return .both
        }
    }
}

/// 保存到文件时的格式。PNG 默认做减色压缩；质量只用于 JPEG 和 WebP。
enum ImageFileFormat: String {
    case png
    case losslessPng
    case jpeg
    case webp

    var usesQuality: Bool { self == .jpeg || self == .webp }

    var fileExtension: String {
        switch self {
        case .png, .losslessPng: return "png"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        }
    }
}

enum AppPreferences {
    private static let keyCodeKey = "hotkeyKeyCode"
    private static let modifiersKey = "hotkeyModifiers"
    private static let characterKey = "hotkeyCharacter"
    private static let hotkeyEnabledKey = "hotkeyEnabled"
    private static let directoryKey = "saveDirectory"
    private static let bookmarkKey = "saveDirectoryBookmark"
    private static let destinationKey = "saveDestination"
    private static let imageFormatKey = "imageFormat"
    private static let imageQualityKey = "imageQuality"

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
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Pictures", isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: directoryKey) }
    }

    /// 记住用户选过的目录，并尽量存成安全作用域书签，供沙盒版下次写入。
    static func rememberSaveDirectory(_ url: URL) {
        saveDirectory = url
        storeBookmark(for: url)
    }

    /// 沙盒里用书签访问目录；没有书签时退回路径（开发版未开沙盒，或目录在「图片」权限内）。
    static func withSaveDirectory<T>(_ body: (URL) -> T) -> T {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return body(saveDirectory)
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return body(saveDirectory)
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        if stale { storeBookmark(for: url) }
        if url.path != UserDefaults.standard.string(forKey: directoryKey) {
            UserDefaults.standard.set(url.path, forKey: directoryKey)
        }
        return body(url)
    }

    private static func storeBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    static var destination: SaveDestination {
        get { SaveDestination(rawValue: UserDefaults.standard.string(forKey: destinationKey) ?? "") ?? .clipboard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: destinationKey) }
    }

    /// 默认是减色 PNG。未设置过时不按 JPEG 质量理解。
    static var imageFormat: ImageFileFormat {
        get { ImageFileFormat(rawValue: UserDefaults.standard.string(forKey: imageFormatKey) ?? "") ?? .png }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: imageFormatKey) }
    }

    /// JPEG / WebP 的质量，1...100。默认 90。
    static var imageQuality: Int {
        get {
            guard UserDefaults.standard.object(forKey: imageQualityKey) != nil else { return 90 }
            return min(100, max(1, UserDefaults.standard.integer(forKey: imageQualityKey)))
        }
        set { UserDefaults.standard.set(min(100, max(1, newValue)), forKey: imageQualityKey) }
    }

    /// 未设置过时默认开启。在快捷键栏按 Delete 后关闭，不再响应全局热键。
    static var isHotkeyEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: hotkeyEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: hotkeyEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyEnabledKey) }
    }

    static func clearHotkey() {
        isHotkeyEnabled = false
    }

    /// 快捷键、保存去向、格式、质量和目录都回到初始值。
    static func restoreDefaults() {
        let defaults = UserDefaults.standard
        for key in [keyCodeKey, modifiersKey, characterKey, hotkeyEnabledKey, directoryKey, bookmarkKey, destinationKey, imageFormatKey, imageQualityKey] {
            defaults.removeObject(forKey: key)
        }
    }

    static func shortcutDisplay(character: String = hotkeyCharacter, modifiers: NSEvent.ModifierFlags = hotkeyModifiers) -> String {
        guard isHotkeyEnabled else { return "None" }
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

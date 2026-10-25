//
//  Preferences.swift
//  Lime
//

import AppKit
import SwiftUI

/// Every setting Lime has, stored in UserDefaults. Views bind to the keys with @AppStorage;
/// everything else reads the typed values here, from any thread.
nonisolated enum Prefs {
    enum Key {
        static let enabled = "enabled"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let convertKey = "convertKey"
        static let toolsKey = "toolsKey"
        static let wheelSize = "wheelSize"
        static let glass = "glassStyle"
        static let hoverColor = "hoverColor"
        static let haptics = "haptics"
        static let shrinkDragPreview = "shrinkDragPreview"
        static let saveLocation = "saveLocation"
        static let customFolder = "customFolder"
        static let imageQuality = "imageQuality"
        static let revealWhenDone = "revealWhenDone"
        static let soundWhenDone = "soundWhenDone"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: true,
            Key.showMenuBarIcon: true,
            Key.convertKey: ConvertKey.shift.rawValue,
            Key.toolsKey: ToolsKey.option.rawValue,
            Key.wheelSize: WheelSize.medium.rawValue,
            Key.glass: GlassStyle.clear.rawValue,
            Key.hoverColor: HoverColor.lime.rawValue,
            Key.haptics: true,
            Key.shrinkDragPreview: true,
            Key.saveLocation: SaveLocation.beside.rawValue,
            Key.imageQuality: 0.9,
            Key.revealWhenDone: false,
            Key.soundWhenDone: false,
        ])
    }

    // MARK: Choices

    /// The key held during a drag to bring up formats.
    enum ConvertKey: String, CaseIterable, Identifiable {
        case shift, control
        var id: String { rawValue }
        var flag: NSEvent.ModifierFlags { self == .shift ? .shift : .control }
        var symbol: String { self == .shift ? "⇧" : "⌃" }
        var name: String { self == .shift ? "Shift" : "Control" }
    }

    /// The key held during a drag to bring up tools.
    enum ToolsKey: String, CaseIterable, Identifiable {
        case option, command
        var id: String { rawValue }
        var flag: NSEvent.ModifierFlags { self == .option ? .option : .command }
        var symbol: String { self == .option ? "⌥" : "⌘" }
        var name: String { self == .option ? "Option" : "Command" }
    }

    enum WheelSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var scale: CGFloat {
            switch self {
            case .small: 0.82
            case .medium: 1
            case .large: 1.3
            }
        }
    }

    enum GlassStyle: String, CaseIterable, Identifiable {
        case clear, frosted
        var id: String { rawValue }
    }

    enum HoverColor: String, CaseIterable, Identifiable {
        case lime, mint, sky, grape, rose, sunset
        var id: String { rawValue }

        /// Light and dark ends of the slice's gradient.
        var colors: [Color] {
            switch self {
            case .lime: [Color(red: 0.78, green: 0.94, blue: 0.40), Color(red: 0.49, green: 0.78, blue: 0.13)]
            case .mint: [Color(red: 0.70, green: 0.97, blue: 0.86), Color(red: 0.20, green: 0.78, blue: 0.60)]
            case .sky: [Color(red: 0.68, green: 0.88, blue: 1.00), Color(red: 0.20, green: 0.55, blue: 0.95)]
            case .grape: [Color(red: 0.86, green: 0.74, blue: 1.00), Color(red: 0.55, green: 0.32, blue: 0.90)]
            case .rose: [Color(red: 1.00, green: 0.78, blue: 0.84), Color(red: 0.93, green: 0.33, blue: 0.50)]
            case .sunset: [Color(red: 1.00, green: 0.85, blue: 0.50), Color(red: 0.98, green: 0.52, blue: 0.20)]
            }
        }

        var gradient: LinearGradient {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }

    enum SaveLocation: String, CaseIterable, Identifiable {
        case beside, downloads, folder
        var id: String { rawValue }
        var title: String {
            switch self {
            case .beside: "Next to the original"
            case .downloads: "Downloads"
            case .folder: "A folder I choose"
            }
        }
    }

    // MARK: Current values

    private static var defaults: UserDefaults { .standard }

    static var convertKey: ConvertKey { ConvertKey(rawValue: defaults.string(forKey: Key.convertKey) ?? "") ?? .shift }
    static var toolsKey: ToolsKey { ToolsKey(rawValue: defaults.string(forKey: Key.toolsKey) ?? "") ?? .option }
    static var wheelScale: CGFloat { (WheelSize(rawValue: defaults.string(forKey: Key.wheelSize) ?? "") ?? .medium).scale }
    static var haptics: Bool { defaults.bool(forKey: Key.haptics) }
    static var shrinkDragPreview: Bool { defaults.bool(forKey: Key.shrinkDragPreview) }
    static var revealWhenDone: Bool { defaults.bool(forKey: Key.revealWhenDone) }
    static var soundWhenDone: Bool { defaults.bool(forKey: Key.soundWhenDone) }
    static var hoverColor: HoverColor { HoverColor(rawValue: defaults.string(forKey: Key.hoverColor) ?? "") ?? .lime }

    /// JPEG/HEIC/AVIF quality for conversions, 0.5…1.
    static var imageQuality: Double {
        let value = defaults.double(forKey: Key.imageQuality)
        return value > 0 ? min(max(value, 0.5), 1) : 0.9
    }

    static var saveLocation: SaveLocation {
        SaveLocation(rawValue: defaults.string(forKey: Key.saveLocation) ?? "") ?? .beside
    }

    static var customFolder: URL? {
        get { defaults.string(forKey: Key.customFolder).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: Key.customFolder) }
    }
}

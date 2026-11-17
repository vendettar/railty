import AppKit
import System

/// The icon style for the Railty app.
enum AppIcon: Equatable, Codable, Sendable {
    case official
    case blueprint
    case chalkboard
    case glass
    case holographic
    case microchip
    case paper
    case retro
    case xray
    /// Save full image data to avoid sandboxing issues
    case custom(_ iconFile: Data)

#if !DOCK_TILE_PLUGIN
    init?(config: Ghostty.Config) {
        switch config.macosIcon {
        case .official:
            return nil
        case .blueprint, .chalkboard, .glass, .holographic, .microchip,
             .paper, .retro, .xray:
            // Railty ships a single official icon. Legacy variant values are
            // accepted for config compatibility but use the bundled icon.
            return nil
        case .custom:
            if let data = try? Data(contentsOf: URL(filePath: config.macosCustomIcon, relativeTo: nil)) {
                self = .custom(data)
            } else {
                return nil
            }
        case .customStyle:
            // Ghostty's layer assets are not shipped with Railty; fall back
            // to the bundled Railty icon for this legacy config value.
            return nil
        }
    }
#endif

    func image(in bundle: Bundle) -> NSImage? {
        switch self {
        case .official, .blueprint, .chalkboard, .glass, .holographic,
             .microchip, .paper, .retro, .xray:
            // Built-in variants and custom-style are not bundled; nil lets
            // NSWorkspace/Dock fall back to the compiled Railty app icon.
            return nil
        case let .custom(file):
            return NSImage(data: file)
        }
    }
}

#if !DOCK_TILE_PLUGIN
/// Making sure that `NSWorkspace.shared.setIcon` executes on only one thread at a time
actor AppIconUpdater {
    func update(icon: AppIcon?) {
        UserDefaults.ghostty.appIcon = icon
        // Notify DockTilePlugin to update dock icon
        DistributedNotificationCenter.default()
            .postNotificationName(
                .ghosttyIconDidChange,
                object: nil,
                userInfo: nil,
                deliverImmediately: true,
            )

        NSWorkspace.shared.setIcon(
            icon?.image(in: .main),
            forFile: Bundle.main.bundlePath,
        )
        NSWorkspace.shared.noteFileSystemChanged(Bundle.main.bundlePath)
    }
}
#endif

import AppKit
import System

/// The icon style for the Railty app.
enum AppIcon: Equatable, Codable, Sendable {
    case official
    /// Save full image data to avoid sandboxing issues
    case custom(_ iconFile: Data)

#if !DOCK_TILE_PLUGIN
    init?(config: Ghostty.Config) {
        switch config.macosIcon {
        case .custom:
            if let data = try? Data(contentsOf: URL(filePath: config.macosCustomIcon, relativeTo: nil)) {
                self = .custom(data)
            } else {
                return nil
            }
        default:
            // Railty ships one compiled app icon. Every other `macos-icon`
            // value (official and legacy upstream values accepted by the
            // config parser) resolves to that bundled icon.
            return nil
        }
    }
#endif

    func image(in bundle: Bundle) -> NSImage? {
        switch self {
        case .official:
            // nil lets NSWorkspace/Dock fall back to the compiled Railty icon.
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

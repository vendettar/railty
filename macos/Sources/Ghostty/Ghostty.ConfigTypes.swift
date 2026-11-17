// This file contains the configuration types for Ghostty so that alternate targets
// can get typed information without depending on all the dependencies of GhosttyKit.

extension Ghostty {
    /// A configuration path value that may be optional or required.
    struct ConfigPath: Sendable {
        let path: String
        let optional: Bool
    }

    /// macos-icon
    enum MacOSIcon: String, Sendable {
        case official
        case blueprint
        case chalkboard
        case glass
        case holographic
        case microchip
        case paper
        case retro
        case xray
        case custom
        case customStyle = "custom-style"

        // NOTE: There is no asset-name mapping here. Railty ships one compiled
        // app icon; the app layer resolves every `macos-icon` value (official
        // and the legacy upstream variants accepted by the config parser) to
        // that bundled icon. Only `custom` can override it. The cases remain
        // so the upstream config values keep parsing identically.
    }

    /// macos-icon-frame
    enum MacOSIconFrame: String, Codable {
        case aluminum
        case beige
        case plastic
        case chrome
    }
}

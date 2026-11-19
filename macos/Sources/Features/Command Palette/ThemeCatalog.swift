import AppKit
import SwiftUI

/// A two-tone preview of a theme's background and foreground colors.
struct ThemePreview {
    let background: Color
    let foreground: Color
}

/// A theme available on disk, used by the command palette's theme picker.
struct GhosttyTheme: Identifiable, Hashable {
    let name: String
    let background: NSColor?
    let foreground: NSColor?

    var id: String { name }

    /// A short label describing whether the theme is light or dark.
    var subtitle: String? {
        guard background != nil else { return nil }
        return isLight ? "Light" : "Dark"
    }

    var isLight: Bool {
        guard let background else { return false }
        return background.isLightColor
    }

    var preview: ThemePreview? {
        guard let background else { return nil }
        return ThemePreview(
            background: Color(background),
            foreground: Color(foreground ?? .textColor)
        )
    }
}

/// Enumerates the themes bundled with Railty and those installed by the user.
///
/// Only theme names are scanned up front. Preview colors are read from disk
/// on demand and cached, so opening the picker never blocks on reading
/// hundreds of theme files.
@MainActor
enum GhosttyThemes {
    /// Maps theme names to their file paths. User themes take priority over
    /// bundled themes, matching Ghostty's theme lookup order.
    private static let paths: [String: String] = loadPaths()

    /// All available theme names, sorted alphabetically.
    static let names: [String] = paths.keys.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    /// Returns the theme with the given name, loading its preview colors on
    /// demand.
    static func theme(named name: String) -> GhosttyTheme {
        let colors = colors(for: name)
        return GhosttyTheme(
            name: name,
            background: colors?.background,
            foreground: colors?.foreground
        )
    }

    private struct ThemeColors {
        let background: NSColor?
        let foreground: NSColor?
    }

    private static var colorCache: [String: ThemeColors] = [:]

    private static func colors(for name: String) -> ThemeColors? {
        if let cached = colorCache[name] { return cached }

        guard let path = paths[name],
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let colors = parseColors(contents)
        colorCache[name] = colors
        return colors
    }

    private static func loadPaths() -> [String: String] {
        var result: [String: String] = [:]

        for dir in directories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
                continue
            }

            for name in entries {
                guard !name.hasPrefix("."), result[name] == nil else { continue }

                let path = (dir as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }

                result[name] = path
            }
        }

        return result
    }

    private static func directories() -> [String] {
        var result: [String] = []

        // The user directory has priority over bundled themes, matching
        // Ghostty's theme lookup order.
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        result.append((configHome as NSString).appendingPathComponent("ghostty/themes"))

        if let resources = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty/themes").path {
            result.append(resources)
        }

        return result
    }

    private static func parseColors(_ contents: String) -> ThemeColors {
        var background: NSColor?
        var foreground: NSColor?

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"),
                  let eq = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed[trimmed.index(after: eq)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "background":
                background = NSColor(themeHex: value)
            case "foreground":
                foreground = NSColor(themeHex: value)
            default:
                continue
            }
        }

        return ThemeColors(background: background, foreground: foreground)
    }
}

private extension NSColor {
    /// Parses the `#RRGGBB` or `#RRGGBBAA` values used in theme files.
    convenience init?(themeHex value: String) {
        var hex = value
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8,
              let number = UInt64(hex, radix: 16) else { return nil }

        let red, green, blue, alpha: CGFloat
        if hex.count == 8 {
            red = CGFloat((number >> 24) & 0xFF) / 255
            green = CGFloat((number >> 16) & 0xFF) / 255
            blue = CGFloat((number >> 8) & 0xFF) / 255
            alpha = CGFloat(number & 0xFF) / 255
        } else {
            red = CGFloat((number >> 16) & 0xFF) / 255
            green = CGFloat((number >> 8) & 0xFF) / 255
            blue = CGFloat(number & 0xFF) / 255
            alpha = 1
        }

        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

import AppKit
import SwiftUI

/// A theme available on disk, used by the command palette's theme picker.
struct GhosttyTheme: Identifiable, Hashable {
    let name: String
    let background: NSColor?

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

    var previewColor: Color? {
        background.map { Color($0) }
    }
}

/// Enumerates the themes bundled with Railty and those installed by the user.
enum GhosttyThemes {
    /// All available themes, sorted by name. Loaded once on first use.
    static let all: [GhosttyTheme] = loadAll()

    private static func loadAll() -> [GhosttyTheme] {
        var seen = Set<String>()
        var themes: [GhosttyTheme] = []

        for dir in directories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
                continue
            }

            for name in entries {
                guard !name.hasPrefix("."), !seen.contains(name) else { continue }

                let path = (dir as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }

                seen.insert(name)
                themes.append(load(name: name, at: path))
            }
        }

        return themes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    private static func load(name: String, at path: String) -> GhosttyTheme {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return GhosttyTheme(name: name, background: nil)
        }

        var background: NSColor?
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"),
                  let eq = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "background" else { continue }

            let value = trimmed[trimmed.index(after: eq)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let color = NSColor(themeHex: value) {
                background = color
            }
        }

        return GhosttyTheme(name: name, background: background)
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

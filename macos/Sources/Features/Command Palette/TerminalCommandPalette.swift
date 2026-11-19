import SwiftUI
import GhosttyKit

func sortedTerminalPaletteOptions(_ options: [CommandOption]) -> [CommandOption] {
    options.sorted { lhs, rhs in
        let lhsTitle = lhs.title.replacingOccurrences(of: ":", with: "\t")
        let rhsTitle = rhs.title.replacingOccurrences(of: ":", with: "\t")
        let comparison = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        if let lhsKey = lhs.sortKey, let rhsKey = rhs.sortKey {
            return lhsKey < rhsKey
        }
        return false
    }
}

struct TerminalCommandPaletteView: View {
    /// The surface that this command palette represents.
    let surfaceView: Ghostty.SurfaceView

    /// Set this to true to show the view, this will be set to false if any actions
    /// result in the view disappearing.
    @Binding var isPresented: Bool

    /// The configuration so we can lookup keyboard shortcuts.
    @ObservedObject var ghosttyConfig: Ghostty.Config

    /// The callback when an action is submitted.
    var onAction: ((String) -> Void)

    /// The current level of the palette.
    @State private var mode: PaletteMode = .commands

    private enum PaletteMode: Hashable {
        case commands
        case themes
    }

    var body: some View {
        ZStack {
            if isPresented {
                // The theme picker disables focus-loss dismissal so that
                // selecting themes and using the footer controls keeps the
                // panel open. Catch clicks outside the panel explicitly so
                // clicking away still dismisses it.
                if mode == .themes {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented = false }
                }

                GeometryReader { geometry in
                    VStack {
                        Spacer().frame(height: geometry.size.height * 0.05)

                        ResponderChainInjector(responder: surfaceView)
                            .frame(width: 0, height: 0)

                        Group {
                            switch mode {
                            case .commands:
                                CommandPaletteView(
                                    isPresented: $isPresented,
                                    backgroundColor: ghosttyConfig.backgroundColor,
                                    options: commandOptions
                                )
                                .id(PaletteMode.commands)

                            case .themes:
                                CommandPaletteView(
                                    isPresented: $isPresented,
                                    backgroundColor: ghosttyConfig.backgroundColor,
                                    options: [],
                                    dynamicOptions: themeOptions(for:),
                                    onExit: { isPresented = false },
                                    placeholder: "Search themes…",
                                    maxHeight: 420,
                                    exitsOnFocusLoss: false,
                                    footer: appearanceFooter
                                )
                                .id(PaletteMode.themes)
                            }
                        }
                        .zIndex(1) // Ensure it's on top

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            // When the command palette disappears we need to send focus back to the
            // surface view we were overlaid on top of. There's probably a better way
            // to handle the first responder state here but I don't know it.
            if !newValue {
                mode = .commands

                // Has to be on queue because onChange happens on a user-interactive
                // thread and Xcode is mad about this call on that.
                DispatchQueue.main.async {
                    surfaceView.window?.makeFirstResponder(surfaceView)
                }
            }
        }
    }

    /// All commands available in the command palette.
    private var commandOptions: [CommandOption] {
        // Sort the terminal options. We replace ":" with a character that sorts before space
        // so that "Foo:" sorts before "Foo Bar:". Use sortKey as a tie-breaker
        // for stable ordering when titles are equal.
        [chooseThemeOption] + sortedTerminalPaletteOptions(jumpOptions + terminalOptions)
    }

    /// The entry point to the second-level theme picker.
    private var chooseThemeOption: CommandOption {
        CommandOption(
            title: "Choose Theme…",
            description: "Search and apply a color theme.",
            leadingIcon: "paintpalette",
            dismisses: false,
            id: "choose-theme"
        ) {
            mode = .themes
        }
    }

    /// Custom commands from the command-palette-entry configuration.
    private var terminalOptions: [CommandOption] {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return [] }
        return appDelegate.ghostty.config.commandPaletteEntries
            .filter(\.isSupported)
            .map { c in
                let symbols = appDelegate.ghostty.config.keyboardShortcut(for: c.action)?.keyList
                return CommandOption(
                    title: c.title,
                    description: c.description,
                    symbols: symbols,
                    id: "command:\(c.action)"
                ) {
                    onAction(c.action)
                }
            }
    }

    /// The Ghostty app used to apply and persist theme changes.
    private var ghostty: Ghostty.App? {
        (NSApp.delegate as? AppDelegate)?.ghostty
    }

    /// Appearance controls shown below the theme list.
    private var appearanceFooter: AnyView? {
        guard let ghostty else { return nil }
        return AnyView(ThemeAppearanceControls(ghostty: ghostty, config: ghosttyConfig))
    }

    /// Theme options for the current query. An empty query shows the curated
    /// `theme-cycle` list; any other query searches all available themes.
    private func themeOptions(for query: String) -> [CommandOption] {
        guard let ghostty else { return [] }
        let current = ghostty.currentThemeName

        if query.isEmpty {
            var names = ghostty.config.themeCycle
            if let current, !names.contains(current) {
                names.insert(current, at: 0)
            }

            return names.map { name in
                themeOption(GhosttyThemes.theme(named: name), current: current, ghostty: ghostty)
            }
        }

        return searchThemes(query)
            .prefix(40)
            .map { themeOption(GhosttyThemes.theme(named: $0), current: current, ghostty: ghostty) }
    }

    /// Searches all theme names for the query, ranking prefix matches first.
    private func searchThemes(_ query: String) -> [String] {
        let lower = query.lowercased()
        return GhosttyThemes.names
            .filter { $0.lowercased().contains(lower) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.lowercased().hasPrefix(lower)
                let rhsPrefix = rhs.lowercased().hasPrefix(lower)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private func themeOption(
        _ theme: GhosttyTheme,
        current: String?,
        ghostty: Ghostty.App
    ) -> CommandOption {
        CommandOption(
            title: "Theme: \(theme.name)",
            subtitle: theme.subtitle,
            preview: theme.preview,
            badge: theme.name == current ? "Current" : nil,
            dismisses: false,
            id: "theme:\(theme.name)"
        ) {
            guard theme.name != current else { return }
            ghostty.applyTheme(theme.name)
        }
    }

    /// Commands for jumping to other terminal surfaces.
    private var jumpOptions: [CommandOption] {
        TerminalController.all.flatMap { controller -> [CommandOption] in
            guard let window = controller.window else { return [] }

            let color = (window as? TerminalWindow)?.tabColor
            let displayColor = color != TerminalTabColor.none ? color : nil

            return controller.surfaceTree.map { surface in
                let terminalTitle = surface.title.isEmpty ? window.title : surface.title
                let displayTitle: String
                if let override = controller.titleOverride, !override.isEmpty {
                    displayTitle = override
                } else if !terminalTitle.isEmpty {
                    displayTitle = terminalTitle
                } else {
                    displayTitle = "Untitled"
                }
                let pwd = surface.pwd?.abbreviatedPath
                let subtitle: String? = if let pwd, !displayTitle.contains(pwd) {
                    pwd
                } else {
                    nil
                }

                return CommandOption(
                    title: "Focus: \(displayTitle)",
                    subtitle: subtitle,
                    leadingIcon: "rectangle.on.rectangle",
                    leadingColor: displayColor?.displayColor.map { Color($0) },
                    id: "surface:\(ObjectIdentifier(surface).hexString)",
                    sortKey: ObjectIdentifier(surface)
                ) {
                    NotificationCenter.default.post(
                        name: Ghostty.Notification.ghosttyPresentTerminal,
                        object: surface
                    )
                }
            }
        }
    }

}

/// This is done to ensure that the given view is in the responder chain.
private struct ResponderChainInjector: NSViewRepresentable {
    let responder: NSResponder

    func makeNSView(context: Context) -> NSView {
        let dummy = NSView()
        DispatchQueue.main.async {
            dummy.nextResponder = responder
        }
        return dummy
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

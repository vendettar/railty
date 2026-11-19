import SwiftUI

struct CommandOption: Identifiable, Hashable {
    /// Unique identifier for this option.
    let id: String
    /// The primary text displayed for this command.
    let title: String
    /// Secondary text displayed below the title.
    let subtitle: String?
    /// Tooltip text shown on hover.
    let description: String?
    /// Keyboard shortcut symbols to display.
    let symbols: [String]?
    /// SF Symbol name for the leading icon.
    let leadingIcon: String?
    /// Color for the leading indicator circle.
    let leadingColor: Color?
    /// Two-tone preview block for theme rows.
    let preview: ThemePreview?
    /// Badge text displayed as a pill.
    let badge: String?
    /// Whether to visually emphasize this option.
    let emphasis: Bool
    /// Whether selecting this option dismisses the palette.
    let dismisses: Bool
    /// Sort key for stable ordering when titles are equal.
    let sortKey: ObjectIdentifier?
    /// The action to perform when this option is selected.
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        symbols: [String]? = nil,
        leadingIcon: String? = nil,
        leadingColor: Color? = nil,
        preview: ThemePreview? = nil,
        badge: String? = nil,
        emphasis: Bool = false,
        dismisses: Bool = true,
        id: String? = nil,
        sortKey: ObjectIdentifier? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id ?? UUID().uuidString
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.symbols = symbols
        self.leadingIcon = leadingIcon
        self.leadingColor = leadingColor
        self.preview = preview
        self.badge = badge
        self.emphasis = emphasis
        self.dismisses = dismisses
        self.sortKey = sortKey
        self.action = action
    }

    static func == (lhs: CommandOption, rhs: CommandOption) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var options: [CommandOption]

    /// Options that depend on the current query, appended after the filtered
    /// static options. Used for lazily searched content such as themes.
    var dynamicOptions: ((String) -> [CommandOption])?

    /// Called when the palette is dismissed via Escape. If nil, the palette
    /// closes.
    var onExit: (() -> Void)?

    /// Placeholder text shown in the search field.
    var placeholder: String = "Execute a command…"

    /// Maximum height of the results list.
    var maxHeight: CGFloat = 200

    /// Whether losing text field focus dismisses the palette. Disable this
    /// when the palette contains focusable controls of its own.
    var exitsOnFocusLoss: Bool = true

    /// Optional controls rendered below the results list.
    var footer: AnyView?

    @State private var rawQuery = ""
    @State private var dynamicCache: [CommandOption] = []
    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: String?

    var query: String {
        rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // The options that we should show, taking into account any filtering from
    // the query. Matched options are ranked in the following order:
    // leadingColor > title > subtitle > description.
    var filteredOptions: [CommandOption] {
        let base = if query.isEmpty {
            options
        } else {
            options.filteredAndSorted(query: query)
        }

        guard dynamicOptions != nil else { return base }

        // With no query, surface the curated dynamic options first so they
        // are visible without scrolling.
        return query.isEmpty ? dynamicCache + base : base + dynamicCache
    }

    var selectedOption: CommandOption? {
        guard let selectedIndex else { return nil }
        return if selectedIndex < filteredOptions.count {
            filteredOptions[Int(selectedIndex)]
        } else {
            filteredOptions.last
        }
    }

    /// Recomputes query-dependent options. This only happens when the query
    /// changes so keyboard navigation doesn't rebuild the list.
    private func refreshDynamicOptions() {
        guard let dynamicOptions else { return }
        dynamicCache = dynamicOptions(query)
    }

    var body: some View {
        let scheme: ColorScheme = if NSColor(backgroundColor).isLightColor {
            .light
        } else {
            .dark
        }

        VStack(alignment: .leading, spacing: 0) {
            CommandPaletteQuery(
                query: $rawQuery,
                placeholder: placeholder,
                exitsOnFocusLoss: exitsOnFocusLoss
            ) { event in
                switch event {
                case .exit:
                    if let onExit {
                        onExit()
                    } else {
                        isPresented = false
                    }

                case .submit:
                    if let option = selectedOption, !option.dismisses {
                        option.action()
                        refreshDynamicOptions()
                    } else {
                        isPresented = false
                        selectedOption?.action()
                    }

                case .move(.up):
                    if filteredOptions.isEmpty { break }
                    let current = selectedIndex ?? UInt(filteredOptions.count)
                    selectedIndex = (current == 0)
                        ? UInt(filteredOptions.count - 1)
                        : current - 1

                case .move(.down):
                    if filteredOptions.isEmpty { break }
                    let current = selectedIndex ?? UInt.max
                    selectedIndex = (current >= UInt(filteredOptions.count - 1))
                        ? 0
                        : current + 1

                case .move:
                    // Unknown, ignore
                    break
                }
            }
            .onChange(of: query) { newValue in
                // If the user types a query then we want to make sure the first
                // value is selected. If the user clears the query and we were selecting
                // the first, we unset any selection.
                if !newValue.isEmpty {
                    if selectedIndex == nil {
                        selectedIndex = 0
                    }
                } else {
                    if let selectedIndex, selectedIndex == 0 {
                        self.selectedIndex = nil
                    }
                }

                refreshDynamicOptions()
            }
            .onAppear {
                refreshDynamicOptions()
            }

            Divider()

            CommandTable(
                options: filteredOptions,
                query: query,
                selectedIndex: $selectedIndex,
                hoveredOptionID: $hoveredOptionID,
                maxHeight: maxHeight) { option in
                    if option.dismisses {
                        isPresented = false
                        option.action()
                    } else {
                        option.action()
                        refreshDynamicOptions()
                    }
                }

            if let footer {
                footer
            }
        }
        .onExitCommand {
            if let onExit {
                onExit()
            } else {
                isPresented = false
            }
        }
        .frame(maxWidth: 500)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(backgroundColor)
                    .blendMode(.color)
            }
                .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .shadow(radius: 32, x: 0, y: 12)
        .padding()
        .environment(\.colorScheme, scheme)
        .onChange(of: isPresented) { newValue in
            if !newValue {
                // This is optional, since most of the time
                // there will be a delay before the next use.
                // To keep behavior the same as before, we reset it.
                rawQuery = ""
            }
        }
    }

}

/// The text field for building the query for the command palette.
private struct CommandPaletteQuery: View {
    @Binding var query: String
    var placeholder: String = "Execute a command…"
    var exitsOnFocusLoss: Bool = true
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    init(
        query: Binding<String>,
        placeholder: String = "Execute a command…",
        exitsOnFocusLoss: Bool = true,
        onEvent: ((KeyboardEvent) -> Void)? = nil
    ) {
        _query = query
        self.placeholder = placeholder
        self.exitsOnFocusLoss = exitsOnFocusLoss
        self.onEvent = onEvent
    }

    enum KeyboardEvent {
        case exit
        case submit
        case move(MoveCommandDirection)
    }

    var body: some View {
        ZStack {
            Group {
                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField(placeholder, text: $query)
                .padding()
                .font(.system(size: 20, weight: .light))
                .frame(height: 48)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { focused in
                    if !focused && exitsOnFocusLoss {
                        onEvent?(.exit)
                    }
                }
                .onExitCommand { onEvent?(.exit) }
                .onMoveCommand { onEvent?(.move($0)) }
                .onSubmit { onEvent?(.submit) }
                .onAppear {
                    // Grab focus on the first appearance.
                    // Debug and Release build using Xcode 26.4,
                    // has same issue again
                    // Fixes: https://github.com/ghostty-org/ghostty/issues/8497
                    // SearchOverlay works magically as expected, I don't know
                    // why it's different here, but dispatching to next loop fixes it
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                }
        }
    }
}

private struct CommandTable: View {
    var options: [CommandOption]
    var query: String
    @Binding var selectedIndex: UInt?
    @Binding var hoveredOptionID: String?
    var maxHeight: CGFloat
    var action: (CommandOption) -> Void

    var body: some View {
        if options.isEmpty {
            Text("No matches")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.1.id) { index, option in
                            CommandRow(
                                option: option,
                                query: query,
                                isSelected: {
                                    if let selected = selectedIndex {
                                        return selected == index ||
                                            (selected >= options.count &&
                                                index == options.count - 1)
                                    } else {
                                        return false
                                    }
                                }(),
                                hoveredID: $hoveredOptionID
                            ) {
                                action(option)
                            }
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
                .onChange(of: selectedIndex) { _ in
                    guard let selectedIndex,
                          selectedIndex < options.count else { return }
                    proxy.scrollTo(
                        options[Int(selectedIndex)].id)
                }
            }
        }
    }
}

/// A single row in the command palette.
private struct CommandRow: View {
    let option: CommandOption
    var query: String
    var isSelected: Bool
    @Binding var hoveredID: String?
    var action: () -> Void

    /// True when this row renders a theme preview with its own colors.
    private var showsThemeColors: Bool {
        option.preview != nil
    }

    private var rowForeground: Color {
        option.preview?.foreground ?? .primary
    }

    /// The row background: theme rows always show the theme's own background.
    /// Selection and hover are separate translucent overlays on top of it.
    private var rowBackground: some View {
        ZStack {
            if let preview = option.preview {
                preview.background
            }

            if isSelected {
                Color.accentColor.opacity(option.preview == nil ? 0.2 : 0.3)
            } else if hoveredID == option.id {
                if option.preview == nil {
                    Color.secondary.opacity(0.2)
                } else {
                    Color.accentColor.opacity(0.15)
                }
            }
        }
    }

    private var rowBorderColor: Color {
        if option.preview != nil {
            return isSelected
                ? Color.accentColor
                : Color.accentColor.opacity(hoveredID == option.id ? 0.45 : 0)
        }

        return Color.accentColor.opacity(option.emphasis && !isSelected ? 0.3 : 0)
    }

    private var highlightedTitle: Text {
        guard !query.isEmpty,
              let indices = option.title.matchedIndices(for: query) else {
            return Text(option.title)
                .fontWeight(option.emphasis ? .medium : .regular)
        }

        var attributed = AttributedString(option.title)
        attributed[attributed.startIndex...].font = .body
            .weight(option.emphasis ? .medium : .regular)

        for idx in indices {
            let offset = option.title.distance(from: option.title.startIndex, to: idx)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let attrEnd = attributed.index(attrStart, offsetByCharacters: 1)
            attributed[attrStart..<attrEnd].font = .body.bold()
            if !showsThemeColors {
                attributed[attrStart..<attrEnd].foregroundColor = Color.accentColor
            }
        }

        return Text(attributed)
    }

    private func highlightedSubtitle(_ subtitle: String) -> Text {
        guard !query.isEmpty,
              option.title.matchedIndices(for: query) == nil,
              let indices = subtitle.matchedIndices(for: query) else {
            return Text(subtitle)
        }

        var attributed = AttributedString(subtitle)

        for idx in indices {
            let offset = subtitle.distance(from: subtitle.startIndex, to: idx)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let attrEnd = attributed.index(attrStart, offsetByCharacters: 1)
            attributed[attrStart..<attrEnd].font = .caption.bold()
            if !showsThemeColors {
                attributed[attrStart..<attrEnd].foregroundColor = Color.accentColor
            }
        }

        return Text(attributed)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let color = option.leadingColor {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

                if let icon = option.leadingIcon {
                    Image(systemName: icon)
                        .foregroundStyle(
                            showsThemeColors
                                ? rowForeground
                                : (option.emphasis ? Color.accentColor : .secondary)
                        )
                        .font(.system(size: 14, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    highlightedTitle
                        .foregroundColor(rowForeground)

                    if let subtitle = option.subtitle ?? option.description {
                        highlightedSubtitle(subtitle)
                            .font(.caption)
                            .foregroundStyle(
                                showsThemeColors ? rowForeground.opacity(0.8) : Color.secondary
                            )
                    }
                }

                Spacer()

                if let badge = option.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                showsThemeColors
                                    ? rowForeground.opacity(0.15)
                                    : Color.accentColor.opacity(0.15)
                            )
                        )
                        .foregroundStyle(showsThemeColors ? rowForeground : Color.accentColor)
                }

                if let symbols = option.symbols {
                    ShortcutSymbolsView(symbols: symbols)
                        .foregroundStyle(
                            showsThemeColors ? rowForeground.opacity(0.8) : Color.secondary
                        )
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(rowBackground)
            .overlay(
                Group {
                    if option.preview == nil {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(rowBorderColor, lineWidth: 1.5)
                    } else {
                        Rectangle()
                            .strokeBorder(
                                rowBorderColor,
                                lineWidth: isSelected ? 2 : (hoveredID == option.id ? 1 : 0)
                            )
                    }
                }
            )
            .cornerRadius(option.preview == nil ? 5 : 0)
        }
        .help(option.description ?? "")
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? option.id : nil
        }
    }
}

/// A row of Text representing a shortcut.
private struct ShortcutSymbolsView: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .frame(minWidth: 13)
            }
        }
    }
}

extension String {
    /// Returns the character indices that match `query`, trying a substring match first,
    /// then falling back to initials matching (first letter of each word).
    /// - Returns: `nil` if neither matches.
    func matchedIndices(for query: String) -> [String.Index]? {
        guard !query.isEmpty else { return nil }

        // Prefer substring match.
        if let range = self.range(of: query, options: .caseInsensitive) {
            return Array(self[range].indices)
        }

        // Fall back to initials match.
        let words = self.split(whereSeparator: \.isWhitespace)
        var queryIndex = query.startIndex
        var matched: [String.Index] = []

        for word in words {
            guard queryIndex < query.endIndex else { break }

            if word.first?.lowercased() == query[queryIndex].lowercased() {
                matched.append(word.startIndex)
                queryIndex = query.index(after: queryIndex)
            }
        }

        return queryIndex == query.endIndex ? matched : nil
    }
}

// MARK: - Match score

extension Collection where Element == CommandOption {
    /// Filters to the options matching `query` and ranks them best-first while
    /// maintaining original order: a closer leading color match always wins,
    /// then a title match beats a subtitle match beats a description match.
    func filteredAndSorted(query: String) -> [Element] {
        compactMap { CommandOptionMatch(option: $0, query: query) }
            .sorted {
                ($0.colorScore, $0.textScore) > ($1.colorScore, $1.textScore)
            }
            .map(\.option)
    }
}

/// A scored match of a command option against a palette query.
struct CommandOptionMatch {
    let option: CommandOption
    /// How closely the option's leading color matches a color name in the
    /// query, from 0 (no match) to 1 (exact).
    let colorScore: Double
    /// Which text field matched, ranked: title (3), subtitle (2),
    /// description (1), none (0).
    let textScore: Int

    /// Returns nil if the option doesn't match the query at all.
    init?(option: CommandOption, query: String) {
        let colorScore = Self.colorMatchScore(for: option.leadingColor, query: query)
        let textScore: Int = if option.title.matchedIndices(for: query) != nil {
            3
        } else if option.subtitle?.matchedIndices(for: query) != nil {
            2
        } else if option.description?.matchedIndices(for: query) != nil {
            1
        } else {
            0
        }

        guard colorScore > 0 || textScore > 0 else { return nil }
        self.option = option
        self.colorScore = colorScore
        self.textScore = textScore
    }

    /// Returns a score (0.0 to 1.0) indicating how well a color matches a search query color name.
    /// Returns 0 if no color name in the query matches, or if the color is nil.
    static func colorMatchScore(for color: Color?, query: String) -> Double {
        guard let color = color else { return 0 }

        let queryLower = query.lowercased()
        let nsColor = NSColor(color)

        var bestScore: Double = 0
        for name in NSColor.colorNames {
            guard queryLower.contains(name),
                  let systemColor = NSColor(named: name) else { continue }

            let distance = nsColor.distance(to: systemColor)
            // Max distance in weighted RGB space is ~3.0, so normalize and invert
            // Use a threshold to determine "close enough" matches
            let maxDistance: Double = 1.5
            if distance < maxDistance {
                let score = 1.0 - (distance / maxDistance)
                bestScore = max(bestScore, score)
            }
        }

        return bestScore
    }
}

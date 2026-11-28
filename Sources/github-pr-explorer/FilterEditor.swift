import AppKit
import GitHubPRExplorerCore
import SwiftUI

// The parts the two filter popovers share, after Figma rows 11 and 13: the Filter popover for
// a search made on the spot (`FilterPopover`) and the popover that edits a saved filter on its
// tab (`SavedFilterPopover`). Each part is built once, here.
//
// A filter is the filter language's: sets joined by OR, each a card of lines joined by AND,
// each line a field, "is" or "is not", and values that are alternatives. The popovers edit a
// `FilterDraft`, and nothing reaches the list or the configuration folder until Apply or Save.

/// How wide both popovers are.
enum FilterPopoverMetrics {
    static let width: CGFloat = 520
    /// The scrolling middle grows with the filter up to this height, then scrolls.
    static let maximumMiddleHeight: CGFloat = 380
    static let fieldWidth: CGFloat = 128
    static let operatorWidth: CGFloat = 76
}

/// The fixed top of a popover: a title (or the name field), something at its trailing end, and
/// the filter said in plain words under them.
struct FilterPopoverHeader<Title: View, Trailing: View>: View {
    let summary: String
    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                title
                Spacer(minLength: 8)
                trailing
            }
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
                .textSelection(.enabled)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: summary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// The scrolling middle: one card per set, an OR divider between sets, and a way to start
/// when there is nothing yet. It grows with the filter and scrolls once it is tall.
struct FilterSetsEditor: View {
    @Binding var draft: FilterDraft
    let model: AppModel
    /// The line whose value picker opens on its own, such as one just added.
    @State private var pickingConditionID: Int?
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if draft.sets.isEmpty {
                        FilterStarter(model: model) { field, value in
                            let id = draft.addSet(field: field)
                            if let value { draft.addValue(value, to: id) } else { pickingConditionID = id }
                        }
                    }
                    ForEach(Array(draft.sets.enumerated()), id: \.element.id) { position, set in
                        if position > 0 {
                            OrDivider()
                                .transition(.opacity)
                        }
                        FilterSetCard(draft: $draft, set: set, model: model, pickingConditionID: $pickingConditionID)
                            .id(set.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                                    removal: .opacity))
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 60), FilterPopoverMetrics.maximumMiddleHeight))
            .scrollBounceBehavior(.basedOnSize)
            .animation(.snappy(duration: 0.22), value: draft.sets.map(\.id))
            // A set added at the end scrolls into view.
            .onChange(of: draft.sets.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.snappy) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }
}

/// What the middle shows before there is any condition: a sentence, a few one-click starts
/// drawn from the commonest searches, and every field.
struct FilterStarter: View {
    let model: AppModel
    let start: (FilterField, String?) -> Void

    private var suggestions: [(title: String, field: FilterField, value: String)] {
        [("Waiting on me", .reviewState, FilterValues.waitingOnMe),
         ("By me", .author, FilterValues.me),
         ("Blocked", .status, StatusSentence.Badge.blocked.rawValue),
         ("Changes requested", .status, StatusSentence.Badge.changesRequested.rawValue),
         ("Not a draft", .draft, "false")]
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No conditions yet, so every open pull request matches.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            WrappingLayout(spacing: 6, lineSpacing: 6, alignment: .center) {
                ForEach(suggestions, id: \.title) { suggestion in
                    Button {
                        start(suggestion.field, suggestion.value)
                    } label: {
                        Text(suggestion.title)
                            .font(.system(size: 12))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Start with \u{201C}\(suggestion.title.lowercased())\u{201D}")
                }
            }
            AddConditionMenu(title: "Add Condition") { field in start(field, nil) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// The centered OR between two sets.
struct OrDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Style.hairline).frame(height: 1)
            Text("OR")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
            Rectangle().fill(Style.hairline).frame(height: 1)
        }
        .padding(.vertical, 10)
        .accessibilityElement()
        .accessibilityLabel("Or")
    }
}

/// One set of conditions, every one of which must match: a rounded card of lines with
/// "+ Add Condition" at its foot.
struct FilterSetCard: View {
    @Binding var draft: FilterDraft
    let set: FilterDraft.ConditionSet
    let model: AppModel
    @Binding var pickingConditionID: Int?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(set.conditions) { condition in
                FilterConditionLine(draft: $draft, condition: condition, model: model, pickingConditionID: $pickingConditionID)
                    .transition(.opacity)
            }
            HStack {
                AddConditionMenu(title: "Add Condition", used: Set(set.conditions.map(\.field))) { field in
                    pickingConditionID = draft.addCondition(toSet: set.id, field: field)
                }
                Spacer()
                if draft.sets.count > 1 {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { draft.removeSet(set.id) }
                    } label: {
                        Label("Remove Set", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0.0001)
                    .help("Remove this set")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Style.hairline))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: set.conditions.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set of conditions, all must match")
    }
}

/// "+ Add Condition": a menu of fields, the ones the set does not use yet first. Choosing one
/// adds the line and opens its values.
struct AddConditionMenu: View {
    let title: String
    var used: Set<FilterField> = []
    let add: (FilterField) -> Void

    var body: some View {
        Menu {
            ForEach(FilterField.allCases.filter { !used.contains($0) }) { field in
                Button(field.name) { add(field) }
            }
            if !used.isEmpty {
                Divider()
                ForEach(FilterField.allCases.filter { used.contains($0) }) { field in
                    Button("Another \(field.name.lowercased())") { add(field) }
                }
            }
        } label: {
            Label(title, systemImage: "plus")
                .font(.system(size: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .tint(.accentColor)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
    }
}

/// One line: the field, "is" or "is not", the values as tokens joined by a small "or", a + to
/// add a value, and a way to remove the line.
struct FilterConditionLine: View {
    @Binding var draft: FilterDraft
    let condition: FilterDraft.Condition
    let model: AppModel
    @Binding var pickingConditionID: Int?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Picker("Field", selection: Binding(get: { condition.field }, set: { draft.setField($0, of: condition.id) })) {
                ForEach(FilterField.allCases) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: FilterPopoverMetrics.fieldWidth)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            Picker("Operator", selection: Binding(get: { condition.operator }, set: { draft.setOperator($0, of: condition.id) })) {
                ForEach(FilterOperator.allCases) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: FilterPopoverMetrics.operatorWidth)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            WrappingLayout(spacing: 4, lineSpacing: 5) {
                ForEach(Array(condition.values.enumerated()), id: \.element) { position, value in
                    if position > 0 {
                        Text("or")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 1)
                            .frame(height: 22)
                    }
                    ValueToken(title: model.filterValueNames.title(value, field: condition.field),
                               value: value, isNot: condition.operator == .isNot) {
                        withAnimation(.snappy(duration: 0.15)) { draft.removeValue(value, from: condition.id) }
                    }
                }
                AddValueButton(draft: $draft, condition: condition, model: model,
                               isPicking: Binding(get: { pickingConditionID == condition.id },
                                                  set: { pickingConditionID = $0 ? condition.id : nil }))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.firstTextBaseline) { _ in 15 }

            Button {
                withAnimation(.snappy(duration: 0.2)) { draft.removeCondition(condition.id) }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.0001)
            .help("Remove this condition")
            .accessibilityLabel("Remove condition")
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .onHover { hovering = $0 }
    }
}

/// A chosen value: its name in a tinted capsule with a × that removes it. Under "is not" the
/// capsule is struck through in tone, so the line reads at a glance.
struct ValueToken: View {
    let title: String
    let value: String
    var isNot = false
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
                .strikethrough(isNot, color: Color.accentColor.opacity(0.5))
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(title)")
            .accessibilityLabel("Remove \(title)")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.accentColor)
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.13)))
        .help(title == value ? title : "\(title) (\(value))")
    }
}

/// The + at the end of a line's values. It opens the value picker, and on a line with no value
/// yet it says what to do.
struct AddValueButton: View {
    @Binding var draft: FilterDraft
    let condition: FilterDraft.Condition
    let model: AppModel
    @Binding var isPicking: Bool

    var body: some View {
        Button {
            isPicking = true
        } label: {
            if condition.values.isEmpty {
                Label("Choose a value", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.5),
                                                                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 22)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(condition.field == .draft ? "Choose Yes or No" : "Add another \(condition.field.name.lowercased()), as an alternative")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            ValuePicker(draft: $draft, conditionID: condition.id, choices: model.valueChoices(for: condition.field)) {
                isPicking = false
            }
        }
    }
}

/// The values a line can take, each with how many open pull requests have it, to tick on and
/// off. Typing narrows the list, the arrow keys move, and Return ticks the highlighted value or
/// takes a typed name the index does not hold yet. Escape closes it.
struct ValuePicker: View {
    @Binding var draft: FilterDraft
    let conditionID: Int
    let choices: FilterValueChoices
    var close: () -> Void = {}
    /// A render passes what is typed.
    var initialText = ""
    @State private var text = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var chosen: [String] { draft.condition(conditionID)?.values ?? [] }
    private var shown: [FilterValueChoices.Choice] { choices.matching(text) }
    private var typedValue: String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard choices.accepts(typed: typed), !shown.contains(where: { $0.value.lowercased() == typed.lowercased() }) else { return nil }
        return typed
    }
    private var needsSearch: Bool { choices.choices.count > 8 || FilterValues.fixed(for: choices.field) == nil }

    var body: some View {
        VStack(spacing: 0) {
            if needsSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit(chooseHighlighted)
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.7)))
                .padding(8)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        if let typedValue {
                            row(title: "Use \u{201C}\(typedValue)\u{201D}", detail: "not in the index yet", count: nil,
                                isChosen: false, isHighlighted: highlighted == -1, symbol: "plus.circle") {
                                draft.addValue(typedValue, to: conditionID)
                                text = ""
                            }
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { position, choice in
                            row(title: choice.title, detail: choice.detail, count: choice.count,
                                isChosen: chosen.contains(choice.value), isHighlighted: position == highlighted, symbol: nil) {
                                highlighted = position
                                toggle(choice)
                            }
                            .id(position)
                        }
                        if shown.isEmpty && typedValue == nil {
                            Text(text.isEmpty ? "Nothing to choose yet." : "No match for \u{201C}\(text)\u{201D}.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                    }
                    .padding(5)
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: !needsSearch)
                .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
            }
            Divider()
            Text(footnote)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(width: 280)
        .onAppear {
            text = initialText
            searchFocused = true
            highlighted = typedValue == nil ? 0 : -1
        }
        .onChange(of: text) { _, _ in highlighted = typedValue == nil ? 0 : -1 }
        // Without a search field the list itself takes the arrow keys.
        .focusable(!needsSearch)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { chooseHighlighted(); return .handled }
        .onKeyPress(.space) { chooseHighlighted(); return needsSearch ? .ignored : .handled }
    }

    private var placeholder: String {
        switch choices.field {
        case .author: "Name or login"
        case .repository: "Repository, such as acme/api"
        case .organization: "Organization"
        default: "Filter values"
        }
    }

    private var footnote: String {
        choices.field == .draft
            ? "Counts are open pull requests."
            : "Counts are open pull requests. Pick several: any of them matches."
    }

    private func move(_ offset: Int) {
        let lowest = typedValue == nil ? 0 : -1
        highlighted = min(max(lowest, highlighted + offset), max(lowest, shown.count - 1))
    }

    private func chooseHighlighted() {
        if highlighted == -1, let typedValue {
            draft.addValue(typedValue, to: conditionID)
            text = ""
        } else if shown.indices.contains(highlighted) {
            toggle(shown[highlighted])
        }
    }

    private func toggle(_ choice: FilterValueChoices.Choice) {
        withAnimation(.snappy(duration: 0.15)) { draft.toggleValue(choice.value, in: conditionID) }
        // Draft has one value: choosing it is the whole choice.
        if choices.field == .draft { close() }
    }

    private func row(title: String, detail: String?, count: Int?, isChosen: Bool, isHighlighted: Bool, symbol: String?,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol ?? (isChosen ? "checkmark" : ""))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 12)
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail, detail != title {
                    Text(verbatim: detail)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .opacity(count == 0 && !isChosen ? 0.5 : 1)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityValue(count.map { "\($0) open" } ?? "")
    }
}

/// The match count and its breakdown by status, as in "7 of 218 match  3 blocked · 2 waiting ·
/// 2 ready". Each status carries a dot in its badge's color. It follows the edits live.
struct FilterMatchSummary: View {
    let evaluation: FilterEvaluation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(evaluation.countText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()
            if evaluation.byStatus.isEmpty {
                Text("Nothing matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(evaluation.byStatus.prefix(5), id: \.status) { part in
                        HStack(spacing: 4) {
                            Circle().fill(part.status.tone.color).frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(part.text)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .fixedSize()
                    }
                    if evaluation.byStatus.count > 5 {
                        Text("+\(evaluation.byStatus.count - 5) more")
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(evaluation.breakdownText)
            }
        }
        .animation(.snappy(duration: 0.25), value: evaluation.count)
        .accessibilityElement(children: .combine)
    }
}

/// The footer's first row: the match summary and "+ Add a Set".
struct FilterMatchRow: View {
    let evaluation: FilterEvaluation
    let addSet: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            FilterMatchSummary(evaluation: evaluation)
            Spacer(minLength: 10)
            Button(action: addSet) {
                Label("Add a Set", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .help("Add another set of conditions. A pull request matches when any set does.")
            .fixedSize()
        }
    }
}

/// A link-like button in the accent color, for "Save as Filter…" and "Clear All".
struct FilterLinkButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(title, role: role, action: action)
            .buttonStyle(.borderless)
            .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
            .font(.system(size: 12))
            .fixedSize()
    }
}

/// The look of a popover, for renders, which cannot show a real one offscreen.
struct PopoverChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// Lays its children out in rows, wrapping to a new row when one is full.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            if alignment == .center { x += (bounds.width - row.width) / 2 }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

import SwiftUI

struct ExclusionsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pathInput = ""
    @State private var patternInput = ""

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 920

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exclusions & Scan Rules")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Keep high-value paths out of the scan and disable categories you do not want surfaced.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()

                    categoryPreferences
                    ruleEditor(compact: compact)
                    activeRules
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var categoryPreferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Category Preferences")
                .font(.title2.weight(.bold))

            ForEach(ScanCategory.allCases) { category in
                Toggle(isOn: Binding(
                    get: { viewModel.isCategoryEnabled(category) },
                    set: { enabled in viewModel.setCategoryEnabled(category, enabled: enabled) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.headline)
                        Text(category.rationale)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func ruleEditor(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 18) {
                    pathRuleEditor
                    patternRuleEditor
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    pathRuleEditor
                        .frame(maxWidth: .infinity, alignment: .leading)
                    patternRuleEditor
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .glassCard()
    }

    private var activeRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active Rules")
                .font(.title2.weight(.bold))

            if viewModel.rules.isEmpty {
                Text("No exclusions or category overrides yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.kind.rawValue)
                                .font(.headline)
                            Text(rule.value)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let category = rule.category {
                                Text(category.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Remove") {
                            viewModel.removeRule(rule)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.tile)
                    )
                }
            }
        }
        .glassCard()
    }

    private var pathRuleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exclude Path")
                .font(.headline)
            TextField("/Users/you/Projects/keep-safe", text: $pathInput)
                .textFieldStyle(.roundedBorder)
            Button("Add Path Rule") {
                viewModel.addExcludedPath(pathInput)
                pathInput = ""
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var patternRuleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exclude Pattern")
                .font(.headline)
            TextField("/Users/*/Desktop/Archive/*", text: $patternInput)
                .textFieldStyle(.roundedBorder)
            Button("Add Pattern Rule") {
                viewModel.addExcludedPattern(patternInput)
                patternInput = ""
            }
            .buttonStyle(.bordered)
        }
    }
}

import PulsoLinkCore
import SwiftUI

/**
 * 活动设置步里各运动自己的那一块（Android `<Sport>SettingsDetails`）：名额（和这项运动的计数）、装备要求、
 * 这项运动的其他选项。球拍类三项共用一块（场地数 × 每场人数、组别、赛制）。
 */
struct SportSettingsDetails: View {
    let model: CreateEventModel
    let sport: LoopSport

    private var draft: CreateDraft { model.draft }

    var body: some View {
        seats
        Section {
            EquipmentEditor(value: draft.equipment, presets: equipmentPresets(sport), onChange: { value in model.update { $0.equipment = value } }, enabled: !model.isSubmitting)
        } header: {
            Label("create_equipment_section", systemImage: "backpack")
        } footer: {
            Text("create_equipment_section_hint")
        }
        options
    }

    /* ------------------------------ 名额 ------------------------------ */

    @ViewBuilder
    private var seats: some View {
        Section {
            switch sport {
            case .badminton, .tennis, .pickleball:
                WizardCounter(label: "create_court_count_label", value: draft.courtCount, minimum: 1, systemImage: "square.grid.2x2") { model.setCourtCount($0) }
                WizardCounter(label: "create_players_per_court_label", value: draft.playersPerCourt, minimum: 1, systemImage: "person") { model.setPlayersPerCourt($0) }
            case .basketball:
                WizardCounter(label: "sport_option_court_count_label", value: draft.basketballOptions.courtCount, minimum: 1, systemImage: "square.grid.2x2") { value in
                    model.setOptions { $0.basketballOptions.courtCount = value }
                }
            case .golf:
                WizardCounter(label: "sport_option_group_count_label", value: draft.golfOptions.groupCount, minimum: 1, systemImage: "square.grid.2x2") { value in
                    model.setOptions { $0.golfOptions.groupCount = value }
                }
                WizardCounter(label: "sport_option_players_per_group_label", value: draft.golfOptions.playersPerGroup, minimum: 2, maximum: 4, systemImage: "person") { value in
                    model.setOptions { $0.golfOptions.playersPerGroup = value }
                }
            case .tableTennis:
                WizardCounter(label: "sport_option_table_count_label", value: draft.tableTennisOptions.tableCount, minimum: 1, systemImage: "square.grid.2x2") { value in
                    model.setOptions { $0.tableTennisOptions.tableCount = value }
                }
                WizardCounter(label: "sport_option_players_per_table_label", value: draft.tableTennisOptions.playersPerTable, minimum: 1, systemImage: "person") { value in
                    model.setOptions { $0.tableTennisOptions.playersPerTable = value }
                }
            case .football, .baseball, .hiking, .fishing, .ski:
                EmptyView()
            }
            WizardCounter(label: "create_capacity_label", value: draft.capacity, minimum: 1, hint: "create_flow_capacity_hint", systemImage: "person.3") { model.setCapacity($0) }
            WizardCounter(label: "create_waitlist_capacity_label", value: draft.waitlistCapacity, minimum: 0, hint: "create_flow_waitlist_hint", systemImage: "hourglass") { value in
                model.update { $0.waitlistCapacity = value }
            }
        } header: {
            Text((isRacket ? "create_section_capacity" : "create_section_seats") as LocalizedStringKey)
        } footer: {
            Text("create_capacity_section_hint")
        }
    }

    private var isRacket: Bool { [.badminton, .tennis, .pickleball].contains(sport) }

    /* ------------------------------ 选项 ------------------------------ */

    @ViewBuilder
    private var options: some View {
        switch sport {
        case .badminton, .tennis, .pickleball:
            Section("create_section_rules") {
                choice("create_eligibility_label", "figure.dress.line.vertical.figure", draft.eligibilityDivision, label: \.labelKey) { value in model.update { $0.eligibilityDivision = value } }
                choice("create_match_format_label", "list.bullet.clipboard", draft.matchFormat, label: \.labelKey) { value in model.update { $0.matchFormat = value } }
            }
        case .basketball:
            Section("create_section_options_basketball") {
                choice("sport_option_basketball_format_label", "basketball", draft.basketballOptions.basketballFormat, label: \.labelKey) { value in
                    model.setOptions { $0.basketballOptions.basketballFormat = value }
                }
                choice("sport_option_eligibility_division_label", "figure.dress.line.vertical.figure", draft.basketballOptions.eligibilityDivision, label: \.labelKey) { value in
                    model.setOptions { $0.basketballOptions.eligibilityDivision = value }
                }
            }
        case .football:
            Section("create_section_options_football") {
                choice("sport_option_football_format_label", "soccerball", draft.footballOptions.footballFormat, label: \.labelKey) { value in
                    model.setOptions { $0.footballOptions.footballFormat = value }
                }
                choice("sport_option_pitch_surface_label", "leaf", draft.footballOptions.pitchSurface, label: \.labelKey) { value in
                    model.setOptions { $0.footballOptions.pitchSurface = value }
                }
                choice("sport_option_eligibility_division_label", "figure.dress.line.vertical.figure", draft.footballOptions.eligibilityDivision, label: \.labelKey) { value in
                    model.setOptions { $0.footballOptions.eligibilityDivision = value }
                }
            }
        case .baseball:
            Section("create_section_options_baseball") {
                choice("sport_option_baseball_variant_label", "baseball", draft.baseballOptions.baseballVariant, label: \.labelKey) { value in
                    model.setOptions { $0.baseballOptions.baseballVariant = value }
                }
                WizardCounter(label: "sport_option_innings_label", value: draft.baseballOptions.innings, minimum: 5, maximum: 9, systemImage: "timer") { value in
                    model.setOptions { $0.baseballOptions.innings = value }
                }
            }
        case .golf:
            Section("create_section_options_golf") {
                choice("sport_option_golf_holes_label", "flag", draft.golfOptions.golfHoles, label: \.labelKey) { value in
                    model.setOptions { $0.golfOptions.golfHoles = value }
                }
            }
        case .hiking:
            Section("create_section_options_hiking") {
                choice("sport_option_hiking_difficulty_label", "figure.hiking", draft.hikingOptions.hikingDifficulty, label: \.labelKey) { value in
                    model.setOptions { $0.hikingOptions.hikingDifficulty = value }
                }
                WizardField(label: "sport_option_distance_km_label", systemImage: "ruler") {
                    TextField(text: Binding(get: { draft.hikingOptions.distanceKm }, set: { value in model.setOptions { $0.hikingOptions.distanceKm = value } })) {
                        Text("sport_option_distance_km_label")
                    }
                    .keyboardType(.decimalPad)
                }
                WizardCounter(label: "sport_option_elevation_gain_m_label", value: draft.hikingOptions.elevationGainM.isEmpty ? "0" : draft.hikingOptions.elevationGainM, minimum: 0, maximum: 9999, systemImage: "mountain.2") { value in
                    model.setOptions { $0.hikingOptions.elevationGainM = value }
                }
            }
        case .fishing:
            Section("create_section_options_fishing") {
                choice("sport_option_fishing_method_label", "fish", draft.fishingOptions.fishingMethod, label: \.labelKey) { value in
                    model.setOptions { $0.fishingOptions.fishingMethod = value }
                }
                choice("sport_option_catch_policy_label", "arrow.uturn.backward", draft.fishingOptions.catchPolicy, label: \.labelKey) { value in
                    model.setOptions { $0.fishingOptions.catchPolicy = value }
                }
                Toggle("sport_option_requires_license_label", isOn: Binding(get: { draft.fishingOptions.requiresLicense }, set: { value in
                    model.setOptions { $0.fishingOptions.requiresLicense = value }
                }))
            }
        case .ski:
            Section("create_section_options_ski") {
                choice("sport_option_ski_discipline_label", "figure.skiing.downhill", draft.skiOptions.skiDiscipline, label: \.labelKey) { value in
                    model.setOptions { $0.skiOptions.skiDiscipline = value }
                }
                choice("sport_option_ski_skill_level_label", "chart.bar", draft.skiOptions.skiSkillLevel, label: \.labelKey) { value in
                    model.setOptions { $0.skiOptions.skiSkillLevel = value }
                }
                Toggle("sport_option_includes_lift_ticket_label", isOn: Binding(get: { draft.skiOptions.includesLiftTicket }, set: { value in
                    model.setOptions { $0.skiOptions.includesLiftTicket = value }
                }))
            }
        case .tableTennis:
            Section("create_section_options_table_tennis") {
                choice("sport_option_match_format_label", "list.bullet.clipboard", draft.tableTennisOptions.matchFormat, label: \.labelKey) { value in
                    model.setOptions { $0.tableTennisOptions.matchFormat = value }
                }
                choice("sport_option_eligibility_division_label", "figure.dress.line.vertical.figure", draft.tableTennisOptions.eligibilityDivision, label: \.labelKey) { value in
                    model.setOptions { $0.tableTennisOptions.eligibilityDivision = value }
                }
            }
        }
    }

    /** 几个选项里选一个：三个以内用分段控件，更多用菜单（Android `PulsoSegmentedControl`）。 */
    private func choice<Option: CaseIterable & Hashable>(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        _ selected: Option,
        label: KeyPath<Option, LocalizedStringKey>,
        onSelect: @escaping (Option) -> Void
    ) -> some View where Option.AllCases: RandomAccessCollection {
        let options = Array(Option.allCases)
        return WizardField(label: title, systemImage: systemImage) {
            Picker(selection: Binding(get: { selected }, set: onSelect)) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            } label: {
                Text(title)
            }
            .labelsHidden()
            .choicePickerStyle(options.count <= 3 ? .segmented : .menu)
        }
    }
}

/** 运行时在分段控件和菜单之间选（`pickerStyle` 要静态类型）。 */
private enum ChoicePickerStyle {
    case segmented
    case menu
}

private extension View {
    @ViewBuilder
    func choicePickerStyle(_ style: ChoicePickerStyle) -> some View {
        switch style {
        case .segmented: pickerStyle(.segmented)
        case .menu: pickerStyle(.menu)
        }
    }
}

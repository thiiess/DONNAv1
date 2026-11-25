import SwiftUI
import SwiftData

// MARK: - Private supporting types

private enum ProductiveTime: String, CaseIterable, Identifiable {
    case morning, midday, evening, variable
    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:  return "Morgen"
        case .midday:   return "Mittag"
        case .evening:  return "Abend"
        case .variable: return "Variabel"
        }
    }

    var icon: String {
        switch self {
        case .morning:  return "sunrise.fill"
        case .midday:   return "sun.max.fill"
        case .evening:  return "moon.fill"
        case .variable: return "arrow.left.arrow.right"
        }
    }

    var preferredStart: Int {
        switch self {
        case .morning:  return 7
        case .midday:   return 12
        case .evening:  return 18
        case .variable: return 9
        }
    }

    var preferredEnd: Int {
        switch self {
        case .morning:  return 12
        case .midday:   return 17
        case .evening:  return 22
        case .variable: return 17
        }
    }
}

private enum RoutineChoice: String, CaseIterable, Identifiable {
    case sport, learning, skincare, nutrition
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sport:     return "Sport"
        case .learning:  return "Lernen"
        case .skincare:  return "Skincare"
        case .nutrition: return "Ernährung"
        }
    }

    var icon: String {
        switch self {
        case .sport:     return "figure.run"
        case .learning:  return "book.fill"
        case .skincare:  return "sparkles"
        case .nutrition: return "fork.knife"
        }
    }

    var category: RoutineCategory {
        switch self {
        case .sport:     return .sport
        case .learning:  return .learning
        case .skincare:  return .skincare
        case .nutrition: return .nutrition
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .sport:     return 45
        case .learning:  return 60
        case .skincare:  return 15
        case .nutrition: return 30
        }
    }

    var colorHex: String {
        switch self {
        case .sport:     return "#FF6B35"
        case .learning:  return "#4A90D9"
        case .skincare:  return "#BF5AF2"
        case .nutrition: return "#30D158"
        }
    }

    func preferredTime(for productive: ProductiveTime) -> Date? {
        let hour: Int
        switch self {
        case .sport:
            hour = (productive == .evening) ? 18 : 7
        case .learning:
            hour = productive.preferredStart
        case .skincare:
            hour = 8
        case .nutrition:
            hour = 7
        }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())
    }
}

private enum ContextChoice: String, CaseIterable, Identifiable {
    case normal, study, work
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normaler Alltag"
        case .study:  return "Studium"
        case .work:   return "Beruf"
        }
    }

    var subtitle: String {
        switch self {
        case .normal: return "Ausgewogener Alltag ohne besondere Phasen"
        case .study:  return "Prüfungen, Deadlines & Lernphasen"
        case .work:   return "Projekte, Meetings & Berufsalltag"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "house.fill"
        case .study:  return "graduationcap.fill"
        case .work:   return "briefcase.fill"
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("donna_onboarding_completed") private var completed = false

    @State private var step = 0
    @State private var selectedLanguage: String = {
        Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    }()
    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var productiveTime: ProductiveTime = .morning
    @State private var selectedRoutines: Set<RoutineChoice> = []
    @State private var contextMode: ContextChoice = .normal

    private let totalSteps = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress dots at top
                progressDots
                    .padding(.horizontal, DS.Spacing.horizontal)
                    .padding(.top, DS.Spacing.vertical)
                    .padding(.bottom, DS.Spacing.section)

                ScrollView {
                    stepContent
                        .padding(.horizontal, DS.Spacing.horizontal)
                        .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)

                navigationRow
                    .padding(.horizontal, DS.Spacing.horizontal)
                    .padding(.vertical, DS.Spacing.vertical)
                    .background(DS.Colors.backgroundPrimary)
            }
            .background(DS.Colors.backgroundPrimary)
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? DS.Colors.accent : (i < step ? DS.Colors.accent.opacity(0.4) : DS.Colors.separator))
                    .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                    .animation(DS.animation, value: step)
            }
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch step {
            case 0: LanguageStep(selected: $selectedLanguage)
            case 1: SleepStep(bedtime: $bedtime, wakeTime: $wakeTime)
            case 2: ProductiveTimeStep(selected: $productiveTime)
            case 3: RoutinesStep(selected: $selectedRoutines)
            case 4: ContextStep(selected: $contextMode)
            default: PrivacyStep()
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Navigation row

    private var navigationRow: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation(DS.animation) { step -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Zurück")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if step < totalSteps - 1 {
                Button {
                    withAnimation(DS.animation) { step += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text("Weiter")
                        Image(systemName: "chevron.right")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DS.Colors.onAccent)
                    .padding(.horizontal, DS.Spacing.horizontal)
                    .padding(.vertical, 12)
                    .background(DS.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: finish) {
                    Text("Loslegen")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DS.Colors.onAccent)
                        .padding(.horizontal, DS.Spacing.horizontal)
                        .padding(.vertical, 12)
                        .background(DS.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Completion

    private func finish() {
        let handler = CommandHandler(modelContext: modelContext)

        // Sleep window
        _ = handler.execute(.setSleepWindow(bedtime: bedtime, wakeTime: wakeTime))

        // Explicit preferences from onboarding choices
        let preferences: [(key: String, value: String)] = [
            ("app_language",           selectedLanguage),
            ("productive_time_of_day", productiveTime.rawValue),
            ("productive_hours_start", "\(productiveTime.preferredStart)"),
            ("productive_hours_end",   "\(productiveTime.preferredEnd)"),
        ]
        for pref in preferences {
            _ = handler.execute(.setExplicitPreference(key: pref.key, value: pref.value))
        }
        UserDefaults.standard.set(selectedLanguage, forKey: "donna_app_language")

        // Selected starter routines (createRoutine also generates 30 days of occurrences)
        for choice in selectedRoutines {
            let definition = RoutineDefinition(
                title: choice.title,
                frequency: .daily,
                preferredTimeOfDay: choice.preferredTime(for: productiveTime),
                durationMinutes: choice.defaultDurationMinutes,
                priority: .medium,
                category: choice.category,
                colorHex: choice.colorHex
            )
            _ = handler.execute(.createRoutine(definition: definition))
        }

        // Initial context mode
        _ = handler.execute(.activateContextMode(name: contextMode.rawValue, until: nil))

        completed = true
    }
}

// MARK: - Step 1: Language

private struct LanguageStep: View {
    @Binding var selected: String

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "globe",
                title: "Sprache / Language",
                subtitle: "Wähle die Sprache für DONNA\nChoose your language for DONNA"
            )

            HStack(spacing: DS.Spacing.vertical) {
                languageCard(code: "de", flag: "🇩🇪", label: "Deutsch")
                languageCard(code: "en", flag: "🇬🇧", label: "English")
            }
        }
    }

    @ViewBuilder
    private func languageCard(code: String, flag: String, label: String) -> some View {
        let isOn = selected == code
        Button { selected = code } label: {
            VStack(spacing: DS.Spacing.vertical) {
                Text(flag).font(.system(size: 48))
                Text(label)
                    .font(DS.Typography.subheading)
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(isOn ? DS.Colors.accent.opacity(0.15) : DS.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(isOn ? DS.Colors.accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(DS.animation, value: isOn)
    }
}

// MARK: - Step 2: Sleep

private struct SleepStep: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "moon.stars.fill",
                title: "Schlafzeiten",
                subtitle: "DONNA schützt deine Schlafzeit automatisch vor Planungen"
            )

            VStack(spacing: 0) {
                timeRow(label: "Bettzeit", icon: "bed.double.fill", selection: $bedtime)
                Rectangle()
                    .fill(DS.Colors.separator)
                    .frame(height: 1)
                    .padding(.leading, 60)
                timeRow(label: "Aufstehen", icon: "alarm.fill", selection: $wakeTime)
            }
            .dsCard()
        }
    }

    @ViewBuilder
    private func timeRow(label: String, icon: String, selection: Binding<Date>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 28)
            Text(label)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, DS.Spacing.vertical + 4)
    }
}

// MARK: - Step 3: Productive time

private struct ProductiveTimeStep: View {
    @Binding var selected: ProductiveTime

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "sun.max.fill",
                title: "Produktive Zeit",
                subtitle: "Wann bist du am leistungsfähigsten?"
            )

            LazyVGrid(columns: columns, spacing: DS.Spacing.vertical) {
                ForEach(ProductiveTime.allCases) { choice in
                    productiveCard(choice)
                }
            }
        }
    }

    @ViewBuilder
    private func productiveCard(_ choice: ProductiveTime) -> some View {
        let isOn = selected == choice
        Button { selected = choice } label: {
            VStack(spacing: DS.Spacing.vertical) {
                Image(systemName: choice.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isOn ? DS.Colors.accent : DS.Colors.textTertiary)
                Text(choice.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isOn ? DS.Colors.textPrimary : DS.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(isOn ? DS.Colors.accent.opacity(0.12) : DS.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(isOn ? DS.Colors.accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(DS.animation, value: isOn)
    }
}

// MARK: - Step 4: Routines

private struct RoutinesStep: View {
    @Binding var selected: Set<RoutineChoice>

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "arrow.clockwise",
                title: "Erste Routinen",
                subtitle: "Wähle Routinen, die du etablieren möchtest.\nDu kannst sie jederzeit anpassen."
            )

            VStack(spacing: DS.Spacing.vertical) {
                ForEach(RoutineChoice.allCases) { choice in
                    routineRow(choice)
                }
            }
        }
    }

    @ViewBuilder
    private func routineRow(_ choice: RoutineChoice) -> some View {
        let isOn = selected.contains(choice)
        Button {
            withAnimation(DS.animation) {
                if isOn { selected.remove(choice) } else { selected.insert(choice) }
            }
        } label: {
            HStack(spacing: DS.Spacing.vertical) {
                Circle()
                    .fill(DS.Colors.category(choice.category))
                    .frame(width: 8, height: 8)

                Image(systemName: choice.icon)
                    .font(.title3)
                    .foregroundStyle(DS.Colors.category(choice.category))
                    .frame(width: 28)

                Text(choice.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DS.Colors.textPrimary)

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? DS.Colors.accent : DS.Colors.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.vertical, DS.Spacing.vertical)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(isOn ? DS.Colors.accent.opacity(0.08) : DS.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(isOn ? DS.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Context mode

private struct ContextStep: View {
    @Binding var selected: ContextChoice

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "person.fill",
                title: "Kontextmodus",
                subtitle: "Passt DONNAs Vorschläge an deinen Alltag an"
            )

            VStack(spacing: DS.Spacing.vertical) {
                ForEach(ContextChoice.allCases) { choice in
                    contextCard(choice)
                }
            }
        }
    }

    @ViewBuilder
    private func contextCard(_ choice: ContextChoice) -> some View {
        let isOn = selected == choice
        Button { withAnimation(DS.animation) { selected = choice } } label: {
            HStack(spacing: DS.Spacing.vertical) {
                Image(systemName: choice.icon)
                    .font(.title3)
                    .foregroundStyle(isOn ? DS.Colors.accent : DS.Colors.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(choice.subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? DS.Colors.accent : DS.Colors.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.vertical, DS.Spacing.vertical + 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(isOn ? DS.Colors.accent.opacity(0.08) : DS.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(isOn ? DS.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 6: Privacy

private struct PrivacyStep: View {
    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            StepHeader(
                icon: "lock.shield.fill",
                title: "Datenschutz",
                subtitle: "Was passiert mit deinen Daten?"
            )

            VStack(spacing: 0) {
                privacyRow(
                    icon: "iphone",
                    title: "Bleibt auf deinem Gerät",
                    detail: "Kalender, Aufgaben, Routinen, Schlafprofil – alles lokal, nie auf fremden Servern."
                )
                Rectangle()
                    .fill(DS.Colors.separator)
                    .frame(height: 1)
                    .padding(.leading, 60)
                privacyRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Geht an Gemini",
                    detail: "Nur anonymisierter Gesprächstext. Keine Namen, keine Orte, keine IDs."
                )
                Rectangle()
                    .fill(DS.Colors.separator)
                    .frame(height: 1)
                    .padding(.leading, 60)
                privacyRow(
                    icon: "key.fill",
                    title: "API-Schlüssel",
                    detail: "Ausschließlich im iOS Keychain gespeichert – sicher, lokal, niemals in der Cloud."
                )
            }
            .dsCard()

            Link(destination: URL(string: "https://aistudio.google.com")!) {
                HStack {
                    Image(systemName: "key.badge.plus")
                    Text("Kostenlosen API-Schlüssel holen")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(DS.Colors.accent)
                .padding(.horizontal, DS.Spacing.horizontal)
                .padding(.vertical, DS.Spacing.vertical)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(DS.Colors.accent.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .stroke(DS.Colors.accent.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.vertical) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Colors.textPrimary)
                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, DS.Spacing.vertical)
    }
}

// MARK: - Shared step header

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DS.Spacing.vertical) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(DS.Colors.accent)
            Text(title)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

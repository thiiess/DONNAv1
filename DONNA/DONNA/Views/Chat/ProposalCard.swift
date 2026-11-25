import SwiftUI

struct ProposalCard: View {
    let orchestrator: InteractionOrchestrator

    @State private var draft: ProposalDraft?

    var body: some View {
        if orchestrator.phase == .awaitingConsent, let proposal = orchestrator.currentProposal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text((orchestrator.isEditingProposal ? "Vorschlag ändern" : "Vorschlag").uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(DS.Colors.warmAccent)
                    Spacer()
                }

                if orchestrator.isEditingProposal, draft != nil {
                    editor
                } else {
                    Text(proposal)
                        .font(.body)
                        .foregroundStyle(DS.Colors.textPrimary)
                    actions
                }
            }
            .padding(16)
            .background(DS.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(DS.Colors.warmAccent.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Ja / Ändern / Nein

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Bestätigen") {
                orchestrator.confirm()
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Colors.warmAccent)

            if orchestrator.makeProposalDraft() != nil {
                Button("Ändern") {
                    draft = orchestrator.makeProposalDraft()
                    orchestrator.isEditingProposal = draft != nil
                }
                .buttonStyle(.bordered)
                .tint(DS.Colors.warmAccent)
            }

            Button("Ablehnen") {
                orchestrator.reject()
            }
            .buttonStyle(.bordered)
            .tint(DS.Colors.destructive)
        }
    }

    // MARK: - Inline editor

    @ViewBuilder
    private var editor: some View {
        if let binding = Binding($draft) {
            VStack(alignment: .leading, spacing: 10) {
                fields(binding)

                Text(binding.wrappedValue.summary)
                    .font(.caption)
                    .foregroundStyle(DS.Colors.textSecondary)

                HStack(spacing: 12) {
                    Button("Übernehmen") {
                        orchestrator.applyProposalEdit(binding.wrappedValue)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.warmAccent)

                    Button("Abbrechen") {
                        orchestrator.isEditingProposal = false
                        draft = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .tint(DS.Colors.warmAccent)
        }
    }

    @ViewBuilder
    private func fields(_ d: Binding<ProposalDraft>) -> some View {
        switch d.wrappedValue.kind {
        case .event:
            titleField(d)
            DatePicker("Tag", selection: d.date, displayedComponents: .date)
            if !d.wrappedValue.isWholeDay {
                HStack(spacing: 16) {
                    DatePicker("Von", selection: d.start, displayedComponents: .hourAndMinute)
                    DatePicker("Bis", selection: d.end, displayedComponents: .hourAndMinute)
                }
                Stepper(d.wrappedValue.prepMinutes == 0 ? "Keine Vorbereitung davor" : "Vorbereitung davor: \(d.wrappedValue.prepMinutes) Min",
                        value: d.prepMinutes, in: 0...120, step: 15)
            }
        case .task:
            titleField(d)
            Toggle("Fälligkeitsdatum", isOn: d.hasDate)
                .tint(DS.Colors.warmAccent)
            if d.wrappedValue.hasDate {
                DatePicker("Fällig am", selection: d.date, displayedComponents: .date)
            }
        case .routine:
            titleField(d)
            timeAndDuration(d)
        case .routineUpdate:
            timeAndDuration(d)
        case .sleep:
            HStack(spacing: 16) {
                DatePicker("Schlafen", selection: d.start, displayedComponents: .hourAndMinute)
                DatePicker("Aufstehen", selection: d.end, displayedComponents: .hourAndMinute)
            }
        }
    }

    private func titleField(_ d: Binding<ProposalDraft>) -> some View {
        TextField("Titel", text: d.title)
            .textFieldStyle(.roundedBorder)
    }

    private func timeAndDuration(_ d: Binding<ProposalDraft>) -> some View {
        HStack(spacing: 16) {
            DatePicker("Uhrzeit", selection: d.start, displayedComponents: .hourAndMinute)
            Stepper("Dauer: \(d.wrappedValue.durationMinutes) Min",
                    value: d.durationMinutes, in: 5...480, step: 5)
        }
    }
}

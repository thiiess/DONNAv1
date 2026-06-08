import SwiftUI

struct ProposalCard: View {
    let orchestrator: InteractionOrchestrator

    var body: some View {
        if orchestrator.phase == .awaitingConsent, let proposal = orchestrator.currentProposal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Vorschlag")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                }

                Text(proposal)
                    .font(.body)
                    .foregroundStyle(DS.Colors.textPrimary)

                HStack(spacing: 12) {
                    Button("Bestätigen") {
                        orchestrator.confirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.accent)

                    Button("Ablehnen") {
                        orchestrator.reject()
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.Colors.destructive)
                }
            }
            .padding(16)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
    }
}

import SwiftUI

struct ProposalFeedView: View {
    let orchestrator: InteractionOrchestrator

    var body: some View {
        if orchestrator.phase == .awaitingConsent {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ProposalCard(orchestrator: orchestrator)
                }
                .padding(.vertical, 8)
            }
        } else {
            Text("Keine offenen Vorschläge")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 16)
        }
    }
}

import SwiftUI
import SwiftData

// MARK: - BriefingCardView

/// Pinned card at the top of the DONNA tab that surfaces today's morning briefing.
/// The briefing itself is a persisted `ChatMessage` (isBriefing == true); this view
/// only presents the latest undismissed one from today. Dismissing collapses the card
/// via CommandHandler without deleting the underlying message.
struct BriefingCardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<ChatMessage> { $0.isBriefing && !$0.isBriefingDismissed },
        sort: \ChatMessage.timestamp,
        order: .reverse
    ) private var briefings: [ChatMessage]

    private var todaysBriefing: ChatMessage? {
        guard let latest = briefings.first,
              Calendar.current.isDateInToday(latest.timestamp) else { return nil }
        return latest
    }

    var body: some View {
        if let briefing = todaysBriefing {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Colors.warmAccent)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Morgenbriefing", systemImage: "sun.max.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Colors.warmAccent)
                        Spacer()
                        Button {
                            dismiss(briefing)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Briefing schließen")
                    }

                    Text(briefing.content)
                        .font(.callout)
                        .foregroundStyle(DS.Colors.donnaBubbleFg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            // The leading accent bar is a Shape with only a width, which is vertically
            // greedy; fixedSize pins the card to its content height so it doesn't expand
            // to fill the VStack and squeeze the chat feed below.
            .fixedSize(horizontal: false, vertical: true)
            .background(DS.Colors.donnaBubbleBg)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private func dismiss(_ briefing: ChatMessage) {
        withAnimation(DS.animation) {
            _ = CommandHandler(modelContext: modelContext).execute(.dismissBriefing(id: briefing.id))
        }
    }
}

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    Text(message.outputType.badgeLabel.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(DS.Colors.warmAccent.opacity(0.85))
                }

                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? DS.Colors.warmAccent : DS.Colors.donnaBubbleBg)
                    .foregroundStyle(message.role == .user ? DS.Colors.onAccent : DS.Colors.textPrimary)
                    // Speech-bubble shape: the corner next to the speaker stays tight.
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: message.role == .assistant ? 4 : 18,
                        bottomTrailingRadius: message.role == .user ? 4 : 18,
                        topTrailingRadius: 18
                    ))
                    .overlay(alignment: .leading) {
                        // DONNA's messages carry a thin accent rule — her "letterhead".
                        if message.role == .assistant {
                            Capsule()
                                .fill(DS.Colors.warmAccent.opacity(0.7))
                                .frame(width: 2)
                                .padding(.vertical, 8)
                        }
                    }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(DS.Colors.textTertiary)
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 4)
    }
}

extension AIOutputType {
    var badgeLabel: String {
        switch self {
        case .interpretation: return "Einschätzung"
        case .clarification:  return "Rückfrage"
        case .proposal:       return "Vorschlag"
        case .explanation:    return "Erklärung"
        }
    }
}

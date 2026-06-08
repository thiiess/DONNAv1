import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    Text(message.outputType.badgeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(DS.Colors.backgroundSecondary)
                        .clipShape(Capsule())
                }

                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? DS.Colors.warmAccent : DS.Colors.warmLight)
                    .foregroundStyle(message.role == .user ? Color.white : DS.Colors.warmDark)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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

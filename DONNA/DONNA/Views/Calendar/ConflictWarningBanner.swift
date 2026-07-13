import SwiftUI

/// Inline conflict notice for the event sheets. Overlaps are advisory (the user may still
/// save); sleep-window violations are blocks and the sheet disables saving alongside this.
struct ConflictWarningBanner: View {
    let message: String
    let isBlocking: Bool

    private var accent: Color {
        isBlocking ? DS.Colors.destructive : DS.Colors.warmAccent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isBlocking ? "moon.zzz.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(DS.Colors.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.chip))
    }
}

#Preview {
    VStack(spacing: 12) {
        ConflictWarningBanner(message: "Überschneidet sich mit „Zahnarzt“ (14:00–15:00).", isBlocking: false)
        ConflictWarningBanner(message: "Liegt im Schlafschutzfenster (23:00–07:00).", isBlocking: true)
    }
    .padding()
}

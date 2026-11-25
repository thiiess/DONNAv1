import SwiftUI
import SwiftData

// MARK: - ChatView

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var orchestrator: InteractionOrchestrator? = nil
    @State private var inputText = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            BriefingCardView()

            if let orchestrator {
                ProposalFeedView(orchestrator: orchestrator)
                    .frame(maxHeight: orchestrator.phase == .awaitingConsent
                        ? (orchestrator.isEditingProposal ? 380 : 200)
                        : 44)

                Divider()

                ChatMessageList(onSend: handleSend)

                Divider()
            } else {
                Spacer()
                Divider()
            }

            if isSending {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("DONNA denkt …")
                        .font(.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            HStack(spacing: 12) {
                TextField("Schreib an DONNA …", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending || orchestrator == nil || orchestrator?.phase == .awaitingConsent)
                    .onSubmit { handleSend() }

                Button { handleSend() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? DS.Colors.warmAccent : Color.secondary)
                }
                .disabled(!canSend)
            }
            .padding()
        }
        .background(DS.Colors.appBackground)
        .navigationTitle("DONNA")
        .task {
            if orchestrator == nil {
                orchestrator = InteractionOrchestrator(modelContext: modelContext)
            }
        }
        .onAppear {
            markAllAssistantMessagesRead()
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSending &&
        orchestrator != nil &&
        orchestrator?.phase != .awaitingConsent
    }

    private func handleSend() {
        guard let orchestrator, canSend else { return }
        let text = inputText.trimmingCharacters(in: .whitespaces)
        inputText = ""
        isSending = true

        let allMessages = (try? modelContext.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let history = Array(allMessages.suffix(10))

        _ = CommandHandler(modelContext: modelContext).execute(.postUserMessage(content: text))

        Swift.Task { @MainActor in
            await orchestrator.process(userInput: text, conversationHistory: history)
            persistAssistantResponse(orchestrator: orchestrator)
            isSending = false
        }
    }

    private func persistAssistantResponse(orchestrator: InteractionOrchestrator) {
        let content: String
        let outputType: AIOutputType
        switch orchestrator.phase {
        case .clarifying:
            content = orchestrator.currentClarification ?? ""
            outputType = .clarification
        case .awaitingConsent:
            content = orchestrator.currentProposal ?? ""
            outputType = .proposal
        case .blocked:
            content = orchestrator.currentExplanation ?? ""
            outputType = .explanation
        default:
            content = orchestrator.lastAssistantMessage ?? orchestrator.lastError ?? ""
            outputType = .interpretation
        }
        guard !content.isEmpty else { return }
        _ = CommandHandler(modelContext: modelContext)
            .execute(.postAssistantMessage(content: content, outputType: outputType))
    }

    private func markAllAssistantMessagesRead() {
        _ = CommandHandler(modelContext: modelContext).execute(.markAssistantMessagesRead)
        NotificationScheduler.shared.updateBadgeCount(modelContext: modelContext)
    }
}

// MARK: - ChatMessageList

private struct ChatMessageList: View {
    @Environment(\.modelContext) private var modelContext
    // Briefing messages are surfaced as a pinned card (BriefingCardView), so they are
    // excluded from the chronological feed to avoid a duplicate bubble.
    @Query(
        filter: #Predicate<ChatMessage> { !$0.isBriefing },
        sort: \ChatMessage.timestamp
    ) private var messages: [ChatMessage]
    let onSend: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty {
                        Text("Hallo. Was beschäftigt dich heute?")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Spacing.section)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
                // The chat is on screen, so anything DONNA posts now has been seen —
                // otherwise the sidebar badge counts up while the user is reading.
                _ = CommandHandler(modelContext: modelContext).execute(.markAssistantMessagesRead)
                NotificationScheduler.shared.updateBadgeCount(modelContext: modelContext)
            }
            .onAppear { scrollToBottom(proxy: proxy) }
            // Bounded viewport: without this the ScrollView can report its full
            // content height and drive the window to grow with the chat history.
            .frame(maxHeight: .infinity)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }
}

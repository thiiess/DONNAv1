import Foundation

// MARK: - ParsedAIResponse

struct ParsedAIResponse {
    let outputType: AIOutputType
    /// Human-readable text shown to the user (PROPOSAL_DATA block stripped).
    let content: String
    /// Raw JSON string from [PROPOSAL_DATA]...[/PROPOSAL_DATA], only for .proposal.
    let proposalJSON: String?
}

// MARK: - ResponseParser

struct ResponseParser {

    private let forbiddenPhrases: [String] = [
        "Ich werde",
        "Ich habe",
        "Das wird",
        "Am besten",
        "Du solltest",
        "Ich mache das"
    ]

    private let tagMap: [(tag: String, type: AIOutputType)] = [
        ("[INTERPRETATION]", .interpretation),
        ("[CLARIFICATION]",  .clarification),
        ("[PROPOSAL]",       .proposal),
        ("[EXPLANATION]",    .explanation)
    ]

    // MARK: - Errors

    enum ParseError: LocalizedError {
        case forbiddenPhrase(String)
        case missingTypeTag
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .forbiddenPhrase(let p): return "Antwort verworfen – verbotene Phrase: \"\(p)\""
            case .missingTypeTag:         return "Antwort enthält keinen gültigen Typ-Tag."
            case .emptyContent:           return "Antwort ist nach dem Typ-Tag leer."
            }
        }
    }

    // MARK: - Public API

    func parse(_ rawResponse: String) throws -> ParsedAIResponse {
        for phrase in forbiddenPhrases {
            if rawResponse.contains(phrase) {
                throw ParseError.forbiddenPhrase(phrase)
            }
        }

        let trimmed = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        for (tag, outputType) in tagMap {
            guard trimmed.hasPrefix(tag) else { continue }
            let afterTag = String(trimmed.dropFirst(tag.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !afterTag.isEmpty else { throw ParseError.emptyContent }

            if outputType == .proposal {
                let json = extractProposalJSON(from: afterTag)
                let display = stripProposalData(from: afterTag)
                guard !display.isEmpty else { throw ParseError.emptyContent }
                return ParsedAIResponse(outputType: .proposal, content: display, proposalJSON: json)
            }

            return ParsedAIResponse(outputType: outputType, content: afterTag, proposalJSON: nil)
        }

        throw ParseError.missingTypeTag
    }

    // MARK: - Proposal extraction helpers

    private func extractProposalJSON(from content: String) -> String? {
        guard let start = content.range(of: "[PROPOSAL_DATA]"),
              let end   = content.range(of: "[/PROPOSAL_DATA]"),
              start.upperBound <= end.lowerBound else { return nil }
        return String(content[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripProposalData(from content: String) -> String {
        if let start = content.range(of: "[PROPOSAL_DATA]") {
            return String(content[..<start.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content
    }
}

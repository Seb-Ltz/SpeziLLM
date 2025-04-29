//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziLLM

public enum LLMOpenAIVoiceError: LLMError {
    /// OpenAI API token is missing.
    case unknown(any Error)
    case string(String)
    
    public static func == (lhs: LLMOpenAIVoiceError, rhs: LLMOpenAIVoiceError) -> Bool {
        switch (lhs, rhs) {
        case let (.unknown(err1), .unknown(err2)): err1.localizedDescription == err2.localizedDescription
        case let (.string(err1), .string(err2)): err1 == err2
        default: false
        }
    }
}

//
//  LLMOpenAIVoiceError.swift
//  SpeziLLM
//
//  Created by Sébastien Letzelter on 16.04.25.
//

import SpeziLLM

public enum LLMOpenAIVoiceError: LLMError {
    /// OpenAI API token is missing.
    case unknown(any Error)
    
    public static func == (lhs: LLMOpenAIVoiceError, rhs: LLMOpenAIVoiceError) -> Bool {
        switch (lhs, rhs) {
        case let (.unknown(err1), .unknown(err2)): err1.localizedDescription == err2.localizedDescription
        }
    }
}

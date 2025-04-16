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
    
    public static func == (lhs: LLMOpenAIVoiceError, rhs: LLMOpenAIVoiceError) -> Bool {  // swiftlint:disable:this cyclomatic_complexity
        switch (lhs, rhs) {
        case (.unknown(let err1), .unknown(let err2)): err1.localizedDescription == err2.localizedDescription
        }
    }
}

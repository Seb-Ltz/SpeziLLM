//
//  LLMOpenAIVoiceSchema.swift
//  SpeziLLM
//
//  Created by Sébastien Letzelter on 09.04.25.
//

import Spezi
import SpeziLLM

public struct LLMOpenAIVoiceSchema: LLMSchema, @unchecked Sendable {
    public typealias Platform = LLMOpenAIVoicePlatform

    let functions: [String: any LLMFunction]
    public var injectIntoContext: Bool
    
    public init(
        injectIntoContext: Bool = false,
        @LLMFunctionBuilder _ functionsCollection: @escaping () -> _LLMFunctionCollection = { LLMOpenAISchema.Defaults.emptyLLMFunctions }
    ) {
        self.injectIntoContext = injectIntoContext
        self.functions = functionsCollection().functions
    }
}

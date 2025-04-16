//
//  LLMOpenAIVoiceSchema.swift
//  SpeziLLM
//
//  Created by Sébastien Letzelter on 09.04.25.
//

import Spezi
import SpeziLLM
import SpeziLLMOpenAI

public struct LLMOpenAIVoiceSchema: LLMSchema, @unchecked Sendable {
    public typealias Platform = LLMOpenAIVoicePlatform
    public enum Defaults {
        /// Empty default of passed function calls (`_LLMFunctionCollection`).
        /// Reason: Cannot use internal init of `_LLMFunctionCollection` as default parameter within public ``LLMOpenAISchema/init(parameters:modelParameters:injectIntoContext:_:)``.
        nonisolated(unsafe) public static let emptyLLMFunctions: _LLMFunctionCollection = .init(functions: [])
    }
    

    let functions: [String: any LLMFunction]
    public var injectIntoContext: Bool
    
    public init(
        injectIntoContext: Bool = false,
        @LLMFunctionBuilder _ functionsCollection: @escaping () -> _LLMFunctionCollection = { Defaults.emptyLLMFunctions }
    ) {
        self.injectIntoContext = injectIntoContext
        self.functions = functionsCollection().functions
    }
}


// TODO: Merge with LLMOpenAI

public struct _LLMFunctionCollection {  // swiftlint:disable:this type_name
    var functions: [String: any LLMFunction] = [:]
    
    
    init(functions: [any LLMFunction]) {
        for function in functions {
            self.functions[Swift.type(of: function).name] = function
        }
    }
}

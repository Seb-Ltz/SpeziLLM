//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
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

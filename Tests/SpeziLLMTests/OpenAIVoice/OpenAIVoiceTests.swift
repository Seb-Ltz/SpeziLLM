//
//  OpenAIVoiceTests.swift
//  SpeziLLM
//
//  Created by Sébastien Letzelter on 08.04.25.
//

import Foundation
@testable import Spezi
@testable import SpeziLLM
@testable import SpeziLLMOpenAI
import Testing

struct OpenAIVoiceTests {
    @MainActor
    internal func initTestLLMSession(_ schema: LLMOpenAIVoiceSchema) throws -> LLMOpenAIVoiceSession {
        guard let openAIToken = ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"] else {
            fatalError("Missing OPENAI_API_TOKEN environment variable")
        }

        let llmOpenAIPlatform = LLMOpenAIVoicePlatform(configuration: LLMOpenAIVoicePlatformConfiguration(apiToken: openAIToken))

        let runner = LLMRunner { llmOpenAIPlatform }
        try DependencyManager([runner]).resolve()
        runner.configure()

        return llmOpenAIPlatform.callAsFunction(with: schema)
    }


    @Test
    @MainActor
    func testVoice() async throws {
        let schema = LLMOpenAIVoiceSchema()
        
        var context = LLMContext()
        context.append(userInput: "Hello, count from 1 to 5.")

        let llmSession = try initTestLLMSession(schema)
        llmSession.context = context
        
        var oneShot = ""
        for try await stringPiece in try await llmSession.generate() {
            oneShot.append(stringPiece)
            print(oneShot.count)
        }

        print("Final result length: \(oneShot.count)")
        #expect(!oneShot.isEmpty)
    }
}

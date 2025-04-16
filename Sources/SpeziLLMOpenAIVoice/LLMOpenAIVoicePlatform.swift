//
//  LLMOpenAIVoicePlatform.swift
//  SpeziLLM
//
//  Created by Sébastien Letzelter on 16.04.25.
//

import Foundation
import os
import Spezi
import SpeziFoundation
import SpeziKeychainStorage
import SpeziLLM

/// Represents the configuration of the Spezi ``LLMOpenAIVoicePlatform``.
public struct LLMOpenAIVoicePlatformConfiguration: Sendable {
    /// The OpenAI API token on a global basis.
    let apiToken: String?

    public init(apiToken: String? = nil) {
        self.apiToken = apiToken
    }
}


public class LLMOpenAIVoicePlatform: LLMPlatform, DefaultInitializable, @unchecked Sendable {
    /// A Swift Logger that logs important information from the ``LLMOpenAIVoiceSession``.
    static let logger = Logger(subsystem: "edu.stanford.spezi", category: "SpeziLLMOpenAIVoice")

    private let semaphore: AsyncSemaphore
    let configuration: LLMOpenAIVoicePlatformConfiguration

    @MainActor public var state: LLMPlatformState = .idle
    @Dependency(KeychainStorage.self) private var keychainStorage

    /// Creates an instance of the ``LLMOpenAIVoicePlatform``.
    ///
    /// - Parameters:
    ///     - configuration: The configuration of the platform.
    public init(configuration: LLMOpenAIVoicePlatformConfiguration) {
        self.configuration = configuration
        self.semaphore = AsyncSemaphore(value: 1)
    }
    
    /// Convenience initializer for the ``LLMOpenAIVoicePlatform``.
    public required convenience init() {
        self.init(configuration: .init())
    }
    
    public func configure() {
        // If token passed via init
        if let apiToken = configuration.apiToken {
            do {
                try keychainStorage.store(
                    Credentials(username: LLMOpenAIConstants.credentialsUsername, password: apiToken),
                    for: .openAIKey
                )
            } catch {
                preconditionFailure("""
                SpeziLLMOpenAI: Configured OpenAI API token could not be stored within the SpeziSecureStorage.
                """)
            }
        }
    }
    
    public func callAsFunction(with llmVoiceSchema: LLMOpenAIVoiceSchema) -> LLMOpenAIVoiceSession {
        LLMOpenAIVoiceSession(self, schema: llmVoiceSchema, keychainStorage: keychainStorage)
    }
    
    func exclusiveAccess() async throws {
        try await semaphore.waitCheckingCancellation()
        
        if await state != .processing {
            await MainActor.run {
                state = .processing
            }
        }
    }
    
    func signal() async {
        let otherTasksWaiting = semaphore.signal()
        
        if !otherTasksWaiting {
            await MainActor.run {
                state = .idle
            }
        }
    }

}

// TODO: Merge with LLMOpenAI

public enum LLMOpenAIConstants {
    static let credentialsUsername = "OpenAIGPT"
}

extension CredentialsTag {
    static let openAIKey = CredentialsTag.genericPassword(forService: "openai.com")
}

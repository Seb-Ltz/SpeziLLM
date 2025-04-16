//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import os
import SpeziLLM
import SpeziKeychainStorage


@Observable
public final class LLMOpenAIVoiceSession: LLMSession, @unchecked Sendable {
    static let logger = Logger(subsystem: "edu.stanford.spezi", category: "LLMOpenAIVoiceSession")

    @MainActor public var state: LLMState = .uninitialized
    @MainActor public var context: LLMContext = []

    /// A set of `Task`s managing the ``LLMOpenAISession`` output generation.
    @ObservationIgnored private var tasks: Set<Task<(), Never>> = []
    /// Ensuring thread-safe access to the `LLMOpenAISession/task`.
    @ObservationIgnored private var lock = NSLock()
    @ObservationIgnored var sessionCreatedContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored var audioDeltaContinuation: AsyncThrowingStream<String, any Error>.Continuation?

    let platform: LLMOpenAIVoicePlatform
    let schema: LLMOpenAIVoiceSchema
    let keychainStorage: KeychainStorage

    public init(_ platform: LLMOpenAIVoicePlatform, schema: LLMOpenAIVoiceSchema, keychainStorage: KeychainStorage) {
        self.platform = platform
        self.schema = schema
        self.keychainStorage = keychainStorage

//        setup()
    }
    
    @discardableResult
    public func generate() async throws -> AsyncThrowingStream<String, any Error> {
        // Warning, as we generate a new stream, and store it into this class,
        // when calling generate() multiple times in a row, the first streams will never finish
        // as the receive loop will be working on the end audioDeltaContinuations...
        // TODO: Fix this, probably by assigning UUIDs to the events, and having a dict of continuations
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        audioDeltaContinuation = continuation
        
        let task = Task {
            if webSocketTask == nil {
                guard await setup() else {
                    fatalError("Failed setup")
                }
            }
            
            await _generate(continuation: continuation)
        }

        _ = lock.withLock {
            tasks.insert(task)
        }

        return stream
    }
    
    private func setup() async -> Bool {
        await MainActor.run {
            self.state = .loading
        }

        let credentials = try? keychainStorage.retrieveCredentials(
            withUsername: LLMOpenAIConstants.credentialsUsername,
            for: .openAIKey
        )
        
        guard let openAPIKey = credentials?.password ?? platform.configuration.apiToken else {
            Self.logger.warning("Missing OpenAI key credentials or apiToken variable")
            return false
        }
        
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview")!

        var request = URLRequest(url: url)
        request.addValue("Bearer \(openAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        self.webSocketTask = URLSession.shared.webSocketTask(with: request)
        self.webSocketTask?.resume()
        
        let task = Task {
            await self.receiveLoop()
        }

        _ = lock.withLock {
            tasks.insert(task)
        }

        guard await withCheckedContinuation({ continuation in
            self.sessionCreatedContinuation = continuation
        }) else {
            return false
        }
        
        await MainActor.run {
            self.state = .ready
        }

        return true
    }
    
    public func cancel() {
        lock.withLock {
            for task in tasks {
                task.cancel()
            }
        }
    }
    
    deinit {
        cancel()
    }
}

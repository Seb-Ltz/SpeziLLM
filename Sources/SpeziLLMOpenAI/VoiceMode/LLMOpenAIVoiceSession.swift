//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import os
import SpeziKeychainStorage
import SpeziLLM


@Observable
public final class LLMOpenAIVoiceSession: LLMSession, @unchecked Sendable {
    static let logger = Logger(subsystem: "edu.stanford.spezi", category: "LLMOpenAIVoiceSession")

    @MainActor public var state: LLMState = .uninitialized
    @MainActor public var context: LLMContext = []

    /// A set of `Task`s managing the ``LLMOpenAISession`` output generation.
    @ObservationIgnored var tasks: Set<Task<(), Never>> = []
    /// Ensuring thread-safe access to the `LLMOpenAISession/task`.
    @ObservationIgnored var lock = NSLock()
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
    }
    
    @discardableResult
    public func generate() async throws -> AsyncThrowingStream<String, any Error> {
        // Warning: as we generate a new stream, and store it into this class,
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

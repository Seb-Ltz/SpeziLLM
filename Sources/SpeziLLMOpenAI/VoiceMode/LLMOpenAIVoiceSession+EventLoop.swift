//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Combine
import Foundation
import GeneratedOpenAIClient
import OpenAPIURLSession
import os
import SpeziLLM


extension LLMOpenAIVoiceSession {
    protocol LLMOpenAIVoiceEventHandler {
        static var messageType: String { get }

        func execute(with payload: [String: Any]) async throws
    }
    
    struct LLMOpenAIVoiceEventDispatcher {
        private let handlers: [String: any LLMOpenAIVoiceEventHandler]
        
        init(handlers: [any LLMOpenAIVoiceEventHandler]) {
            self.handlers = Dictionary(
                uniqueKeysWithValues: handlers.map { (type(of: $0).messageType, $0) }
            )
        }
        
        func dispatch(_ jsonDict: [String: Any]) async {
            guard let type = jsonDict["type"] as? String,
                  let handler = handlers[type]
            else {
                logger.warning("No handler for type \(jsonDict["type"] as? String ?? "<type missing>")")
                return
            }

            do {
                try await handler.execute(with: jsonDict)
            } catch {
                logger.error("Handler for \(type) threw: \(error)")
            }
        }
    }
    
    func receiveLoop() async {
        guard let task = webSocketTask else {
            return
        }
        
        let dispatcher = LLMOpenAIVoiceEventDispatcher(handlers: [
            HandlerSessionCreated(sessionIsActive: sessionIsActive),
            HandlerAudioResponseDelta { self.audioDeltaContinuation },
            HandlerAudioResponseDone { self.audioDeltaContinuation },
            HandlerResponseDone(session: self),
            HandlerError()
        ])
        
        while true {
            do {
                let message = try await task.receive()
                
                if case let .string(text) = message {
                    guard let messageJsonData = text.data(using: .utf8),
                          let messageDict = try? JSONSerialization.jsonObject(with: messageJsonData, options: [])  as? [String: Any] else {
                        Self.logger.warning("Invalid message format: \(text)")
                        continue
                    }

                    // Dispatch the event message to the correct event handler
                    await dispatcher.dispatch(messageDict)
                    
                    if let type = messageDict["type"] as? String {
                        await MainActor.run {
                            self.lastEventType = type
                        }
                    }
                }
            } catch {
                Self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                audioDeltaContinuation?.finish(throwing: error)
                break
            }
        }
    }
}

extension LLMOpenAIVoiceSession {
    struct HandlerAudioResponseDelta: LLMOpenAIVoiceEventHandler {
        static let messageType = "response.audio.delta"
        
        let getAudioContinuation: () -> AsyncThrowingStream<String, any Error>.Continuation?

        func execute(with payload: [String: Any]) {
            // If present, yield the "delta" value to the stream.
            if let delta = payload["delta"] as? String {
                getAudioContinuation()?.yield(delta)
            } else {
                logger.warning("Missing 'delta' in response.audio.delta event: \(payload)")
            }
        }
    }

    struct HandlerResponseDone: LLMOpenAIVoiceEventHandler {
        static let messageType = "response.done"
        unowned let session: LLMOpenAIVoiceSession
        typealias ConversationItemCreateEvent = Components.Schemas.RealtimeClientEventConversationItemCreate

        func execute(with payload: [String: Any]) async {
            guard
                let response = payload["response"] as? [String: Any],
                let output = response["output"] as? [[String: Any]],
                let first = output.first,
                let type = first["type"] as? String
            else {
                logger.warning("Missing or invalid 'response.output.type' in response.done: \(payload)")
                return
            }

            if type == "function_call" {
                await handleFunctionCall(first)
            }
        }
        
        private func handleFunctionCall(_ payload: [String: Any]) async {
            guard
                let name = payload["name"] as? String,
                let callId = payload["call_id"] as? String,
                let arguments = payload["arguments"] as? String
            else {
                logger.warning("Missing function_call fields in response.done: \(payload)")
                return
            }

            do {
                let argumentData = arguments.data(using: .utf8) ?? Data()

                try session.schema.functions[name]?.injectParameters(from: argumentData)
                let output = try await session.schema.functions[name]?.execute()

                let conversationItem = ConversationItemCreateEvent(
                    _type: .conversation_period_item_period_create,
                    item: .init(
                        _type: .function_call_output,
                        call_id: callId,
                        output: output
                    )
                )
                
                let conversationItemJson = try JSONEncoder().encode(conversationItem)
                try await session.webSocketTask?.send(.string(String(decoding: conversationItemJson, as: UTF8.self)))
                logger.debug("Sent function call result: \(String(decoding: conversationItemJson, as: UTF8.self))")

                try await session.createResponse()
            } catch {
                logger.error("Error handling function call: \(error)")
            }
        }
    }
    
    struct HandlerSessionCreated: LLMOpenAIVoiceEventHandler {
        static let messageType = "session.created"

        private let sessionIsActive: CurrentValueSubject<Bool, Never>

        init(sessionIsActive: CurrentValueSubject<Bool, Never>) {
            self.sessionIsActive = sessionIsActive
        }

        func execute(with payload: [String: Any]) {
            sessionIsActive.send(true)
        }
    }
    
    struct HandlerAudioResponseDone: LLMOpenAIVoiceEventHandler {
        static let messageType = "response.audio.done"

        let getAudioContinuation: () -> AsyncThrowingStream<String, any Error>.Continuation?

        func execute(with payload: [String: Any]) {
            // When done with receiving audio, close the stream.
            getAudioContinuation()?.finish()
        }
    }
    
    struct HandlerError: LLMOpenAIVoiceEventHandler {
        static let messageType = "error"
        
        func execute(with payload: [String: Any]) {
            logger.error("Encountered error: \(payload)")
        }
    }
}

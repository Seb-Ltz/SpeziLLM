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


extension LLMOpenAIVoiceSession {
    // swiftlint:disable:next identifier_name
    func _generate(continuation: AsyncThrowingStream<String, any Error>.Continuation) async {
        do {
            try await commitContext()
        } catch {
            await finishGenerationWithError(LLMOpenAIVoiceError.unknown(error), on: continuation)
        }
    }
    // swiftlint:disable:next function_body_length
    func receiveLoop() async {
        guard let task = webSocketTask else {
            return
        }
        
        while true {
            do {
                let message = try await task.receive()
                
                if case let .string(text) = message {
                    guard let jsonData = text.data(using: .utf8),
                          let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
                          let jsonDict = jsonObject as? [String: Any],
                          let type = jsonDict["type"] as? String else {
                        Self.logger.warning("Invalid message format: \(text)")
                        continue
                    }
                    
                    Self.logger.info("Received WebSocket text message, of type \(type)")
                    
                    // Check if this is an audio delta or done message.
                    if type == "session.created" {
                        Self.logger.info("Session created signal received.")
                        // Resume the continuation if it exists.
                        sessionCreatedContinuation?.resume(returning: true)
                        // Clear the continuation after resuming to avoid multiple resumes.
                        sessionCreatedContinuation = nil
                    } else if type == "response.audio.delta" {
                        // If present, yield the "delta" value to the stream.
                        if let delta = jsonDict["delta"] as? String {
                            audioDeltaContinuation?.yield(delta)
                        } else {
                            Self.logger.warning("Missing 'delta' in audio delta message: \(text)")
                        }
                    } else if type == "response.audio.done" {
                        // When done, close the stream.
                        audioDeltaContinuation?.finish()
                    } else if type == "response.audio_transcript.done" {
                        Self.logger.debug("Final transcript: \(jsonDict["transcript"] as? String ?? "Not found")")
                    } else if type == "response.done" {
                        guard let response = jsonDict["response"] as? [String: Any],
                              let output = response["output"] as? [[String: Any]],
                              let type = output[0]["type"] as? String,
                              let name = output[0]["name"] as? String,
                              let callId = output[0]["call_id"] as? String,
                              let arguments = output[0]["arguments"] as? String,
                              type == "function_call"
                        else {
                            continue
                        }
                        
                        Self.logger.log("arguments function call: \(arguments)")
                        Task {
                            try schema.functions[name]?.injectParameters(from: arguments.data(using: .utf8) ?? Data())
                            let functionOutput = try await schema.functions[name]?.execute()
                            let eventData: [String: Any] = [
                                "type": "conversation.item.create",
                                "item": [
                                    "type": "function_call_output",
                                    "call_id": callId,
                                    "output": functionOutput
                                ]
                            ]
                            
                            let eventDataJson = try JSONSerialization.data(withJSONObject: eventData, options: .prettyPrinted)

                            let responseData: [String: Any] = [
                                "type": "response.create"
                            ]
                            let responseDataJson = try JSONSerialization.data(withJSONObject: responseData, options: .prettyPrinted)
                            
                            
                            try await webSocketTask?.send(.string(String(decoding: eventDataJson, as: UTF8.self)))
                            Self.logger.debug("Function call event:\n\(String(decoding: eventDataJson, as: UTF8.self))")
                            
                            try await webSocketTask?.send(.string(String(decoding: responseDataJson, as: UTF8.self)))
                        }
                    } else if type == "error" {
                        Self.logger.error("Encountered error: \(jsonDict)")
                    }
                } else {
                    Self.logger.info("Received WebSocket message, of another type than text")
                }
            } catch {
                Self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                audioDeltaContinuation?.finish(throwing: error)
                break
            }
        }
    }
    
    private func commitContext() async throws {
        let eventData: [String: Any] = await [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content":
                    context
                    .filter { $0.role == .user }
                    .filter { $0.content.starts(with: "text:") }
                    .compactMap { [ "type": "input_text", "text": $0.content.dropFirst("text:".count) ] }
                + context
                    .filter { $0.role == .user }
                    .filter { $0.content.starts(with: "voice:") }
                    .compactMap { [ "type": "input_audio", "audio": $0.content.dropFirst("voice:".count) ] }
            ]
        ]
        
        let eventDataJson = try JSONSerialization.data(withJSONObject: eventData, options: .prettyPrinted)
        
        let responseData: [String: Any] = [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"],
                "instructions": "Please assist the user."
            ]
        ]
        let responseDataJson = try JSONSerialization.data(withJSONObject: responseData, options: .prettyPrinted)
        
        
        try await webSocketTask?.send(.string(String(decoding: eventDataJson, as: UTF8.self)))
        Self.logger.debug("Sent event:\n\(String(decoding: eventDataJson, as: UTF8.self))")
    
        try await webSocketTask?.send(.string(String(decoding: responseDataJson, as: UTF8.self)))
    }
}

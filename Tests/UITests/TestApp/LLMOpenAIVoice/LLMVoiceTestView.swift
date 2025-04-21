//
//  LLMVoiceTestView.swift
//  TestApp
//
//  Created by Sébastien Letzelter on 09.04.25.
//


import AVFoundation
import SpeziLLMOpenAI
import SwiftUI

struct LLMVoiceTestView: View {
    private static let schema = LLMOpenAIVoiceSchema {
        LLMOpenAIFunctionWeather()
    }

    private static var pcmPlayer = PCMPlayer()
    @LLMSessionProvider(schema: Self.schema) var llm: LLMOpenAIVoiceSession

    @State var inputText: String = ""
    @State var isLoading: Bool = false
    @State var oneShotB64: String = ""
    @State var showOnboarding = false
        
    var audioRecorder = AudioRecorder.shared

    
    var body: some View {
        Group {
            VStack {
                TextField("Input", text: $inputText)
                Text("OneShot length: \(oneShotB64.count) characters")
                if !isLoading {
                    Button("Send") {
                        Task {
                            await send(content: inputText)
                        }
                    }
                } else {
                    ProgressView()
                }
                
                HStack {
                    Button(audioRecorder.isRecording ? "Send" : "Record") {
                        if audioRecorder.isRecording {
                            audioRecorder.stop()
                            Self.pcmPlayer.play(rawPCMData: audioRecorder.base64PCM)
                            Task {
                                await send(content: audioRecorder.base64PCM.base64EncodedString(), isText: false)
                            }
                        } else {
                            checkPermissionAndRecord()
                        }
                    }
                }
            }
        }
        .navigationTitle("LLM_OPENAI_VOICE_VIEW_TITLE")
        .toolbar {
            ToolbarItem {
                Button("LLM_OPENAI_CHAT_ONBOARDING_BUTTON") {
                    showOnboarding.toggle()
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            LLMOpenAIVoiceOnboardingView()
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 550)
                #endif
        }
    }
    
    func send(content: String, isText: Bool = true) async {
        isLoading = true
        print("Content: \(content.count) chars length")
        llm.context.append(userInput: "\(isText ? "text:" : "voice:" )\(content)")

        do {
            var oneShot = ""
            for try await stringPiece in try await llm.generate() {
                oneShot.append(stringPiece)
            }
            oneShotB64 = oneShot
            
            guard let rawData = Data(base64Encoded: oneShotB64) else {
                print("Failed to decode Base64 string")
                return
            }
            Self.pcmPlayer.play(rawPCMData: rawData)
        } catch {
            print(error)
        }
        isLoading = false
        llm.context.removeAll()
    }
    
    func checkPermissionAndRecord() {
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                DispatchQueue.main.async {
                    audioRecorder.start()
                }
            } else {
                print("Microphone permission denied")
            }
        }
    }
}

#Preview {
    LLMVoiceTestView()
}

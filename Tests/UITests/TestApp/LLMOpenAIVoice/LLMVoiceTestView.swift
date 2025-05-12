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
        Group { // swiftlint:disable:this closure_body_length
            VStack {
                HStack {
                    Circle()
                        .frame(width: 12, height: 12)
                        .foregroundColor(llm.isSessionActive ? .green : .red)
                    Text(llm.isSessionActive ? "Connected" : "Disconected")
                }
                
                Text(llm.lastEventType)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                TextField("Input", text: $inputText)
                Text("OneShot length: \(oneShotB64.count) characters")
                if !isLoading {
                    Button("Send") {
                        Task {
                            llm.context.append(userInput: inputText)
                            await send()
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
                                llm.context.appendAudio(userInput: audioRecorder.base64PCM)
                                await send()
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
    
    func send() async {
        isLoading = true

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

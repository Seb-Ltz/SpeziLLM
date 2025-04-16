//
//  LLMVoiceTestView.swift
//  TestApp
//
//  Created by Sébastien Letzelter on 09.04.25.
//


import SpeziLLMOpenAIVoice
import SwiftUI

struct LLMVoiceTestView: View {
    private static let schema = LLMOpenAIVoiceSchema()
    private static var pcmPlayer = PCMPlayer()
    @LLMSessionProvider(schema: Self.schema) var llm: LLMOpenAIVoiceSession

    @State var inputText: String = ""
    @State var isLoading: Bool = false
    @State var oneShotB64: String = ""
    @State var showOnboarding = false
    
    var body: some View {
        Group {
            VStack {
                TextField("Input", text: $inputText)
                Text("OneShot length: \(oneShotB64.count) characters")
                if !isLoading {
                    Button("Send") {
                        Task {
                            await send()
                        }
                    }
                } else {
                    ProgressView()
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
        print(inputText)
        llm.context.append(userInput: inputText)
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
}

#Preview {
    LLMVoiceTestView()
}

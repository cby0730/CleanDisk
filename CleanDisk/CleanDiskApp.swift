import SwiftUI
import os.log

@main
struct CleanDiskApp: App {
    // LLM 服務
    @StateObject private var llmService = LLMService()
    
    init() {
        // 減少系統日誌的警告訊息
        if #available(macOS 11.0, *) {
            let logger = Logger(subsystem: "com.yourcompany.CleanDisk", category: "App")
            logger.info("CleanDisk app starting")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(llmService) // 注入 LLM 服務
                .onAppear {
                    // 應用程式啟動時預載 AI 模型
                    Task {
                        await llmService.loadModel()
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // 可以在這裡添加選單命令
        }
    }
}

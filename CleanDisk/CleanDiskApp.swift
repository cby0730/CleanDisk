import SwiftUI
import os.log

@main
struct CleanDiskApp: App {
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
                .onAppear {
                    // 應用程式啟動時的初始化
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // 可以在這裡添加選單命令
        }
    }
}

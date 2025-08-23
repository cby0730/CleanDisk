import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = FileSystemScanner()
    @State private var selectedPath = "/"
    
    var body: some View {
        NavigationSplitView {
            // 側邊欄 - 路徑選擇和掃描控制
            SidebarControlPanel(scanner: scanner, selectedPath: $selectedPath)
            
        } detail: {
            // 主要區域
            if let rootNode = scanner.rootNode {
                VStack(spacing: 0) {
                    // 上半部：檔案樹和詳細資訊
                    HStack(spacing: 0) {
                        // 檔案樹
                        FileTreeView(node: rootNode)
                            .environmentObject(scanner)
                            .frame(minWidth: 400)
                        
                        Divider()
                        
                        // 詳細資訊面板
                        DetailPanel(selectedNode: scanner.selectedNode)
                            .frame(width: 300)
                    }
                    .frame(minHeight: 400)
                    
                    Divider()
                    
                    // 下半部：刪除區域
                    DeletionZone(
                        deletionService: scanner.deletionService,
                        scanner: scanner
                    )
                    .frame(maxHeight: 200)
                }
            } else {
                MainAreaEmptyState()
            }
        }
    }
}

/// 主要區域空狀態
struct MainAreaEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("選擇路徑並開始掃描")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("預設會掃描 Macintosh HD (/)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}

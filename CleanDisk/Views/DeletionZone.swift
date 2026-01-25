import SwiftUI

/// 刪除區域組件
struct DeletionZone: View {
    @ObservedObject var deletionService: FileDeletionService
    @ObservedObject var scanner: FileSystemScanner
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 拖拉目標區域
            DeletionDropTarget(
                isTargeted: $isTargeted,
                onDrop: handleDrop
            )
            
            // 待刪除項目列表
            if !deletionService.deletionQueue.isEmpty {
                DeletionQueueView(
                    deletionService: deletionService,
                    scanner: scanner
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // 在閉包外部捕獲需要的引用（避免在閉包中捕獲整個 self）
        let deletionService = self.deletionService
        let scanner = self.scanner
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadObject(ofClass: NSURL.self) { [weak deletionService, weak scanner] url, error in
                    // 使用 weak 引用，如果視圖已消失則提前退出
                    guard let url = url as? URL,
                          let deletionService = deletionService,
                          let scanner = scanner else { return }
                    
                    // 使用快取進行 O(1) 查找，避免遍歷整棵樹
                    if let node = scanner.findNode(by: url) {
                        DispatchQueue.main.async {
                            deletionService.addToDeletionQueue(node)
                        }
                    }
                }
            }
        }
        return true
    }
}

/// 拖拉目標區域
struct DeletionDropTarget: View {
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isTargeted ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
            .stroke(isTargeted ? Color.red : Color.gray.opacity(0.3), lineWidth: 2)
            .frame(height: 80)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(isTargeted ? .red : .secondary)
                    Text(isTargeted ? "放開以添加到刪除列表" : "拖拉檔案到此處刪除")
                        .font(.caption)
                        .foregroundColor(isTargeted ? .red : .secondary)
                }
            )
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted, perform: onDrop)
    }
}

/// 待刪除項目列表視圖
struct DeletionQueueView: View {
    @ObservedObject var deletionService: FileDeletionService
    @ObservedObject var scanner: FileSystemScanner
    
    /// 生成確認刪除對話框的檔案清單訊息
    private var deletionConfirmationMessage: String {
        let queue = deletionService.deletionQueue
        let totalSize = ByteCountFormatter.string(fromByteCount: deletionService.deletionQueueTotalSize, countStyle: .file)
        
        var message = "即將刪除以下項目：\n"
        
        // 最多顯示前 5 個檔案名稱
        let maxDisplay = 5
        let displayItems = queue.prefix(maxDisplay)
        
        for (index, node) in displayItems.enumerated() {
            let icon = node.isDirectory ? "📁" : "📄"
            let size = node.formattedSize
            message += "\(index + 1). \(icon) \(node.name) (\(size))\n"
        }
        
        // 如果超過 5 個，顯示還有多少個
        if queue.count > maxDisplay {
            let remaining = queue.count - maxDisplay
            message += "...還有 \(remaining) 個項目\n"
        }
        
        message += "\n總大小: \(totalSize)\n這些項目將被移動到垃圾桶。"
        
        return message
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeletionQueueHeader(deletionService: deletionService)
            
            // 項目列表
            if deletionService.deletionQueue.isEmpty {
                DeletionQueueEmptyState()
            } else {
                DeletionQueueList(deletionService: deletionService)
            }
            
            // 操作按鈕
            if !deletionService.deletionQueue.isEmpty {
                DeletionQueueActions(
                    deletionService: deletionService,
                    scanner: scanner
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .cornerRadius(8)
        .confirmationDialog(
            "確認刪除",
            isPresented: $deletionService.showDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("刪除 \(deletionService.deletionQueue.count) 個項目", role: .destructive) {
                deletionService.executeFileDeletion { deletedNodes in
                    // 使用回傳的成功刪除節點來更新檔案樹
                    if !deletedNodes.isEmpty {
                        scanner.updateFileTreeAfterDeletion(deletedNodes: deletedNodes)
                    }
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(deletionConfirmationMessage)
        }
    }
}

/// 刪除隊列標題
struct DeletionQueueHeader: View {
    @ObservedObject var deletionService: FileDeletionService
    
    var body: some View {
        HStack {
            Text("待刪除項目 (\(deletionService.deletionQueue.count))")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("總大小: \(ByteCountFormatter.string(fromByteCount: deletionService.deletionQueueTotalSize, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 刪除隊列空狀態
struct DeletionQueueEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundColor(.secondary)
                .font(.title2)
            
            Text("拖拉檔案或資料夾到此處加入刪除列表")
                .foregroundColor(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: 80)
        .frame(maxWidth: .infinity)
    }
}

/// 刪除隊列列表
struct DeletionQueueList: View {
    @ObservedObject var deletionService: FileDeletionService
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 4) {
                ForEach(deletionService.deletionQueue) { node in
                    DeletionQueueItem(node: node, deletionService: deletionService)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 60, maxHeight: 200)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

/// 刪除隊列操作按鈕
struct DeletionQueueActions: View {
    @ObservedObject var deletionService: FileDeletionService
    @ObservedObject var scanner: FileSystemScanner
    
    var body: some View {
        HStack {
            Button("清空列表") {
                deletionService.clearDeletionQueue()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("確認刪除") {
                deletionService.showDeletionConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(deletionService.isDeletingFiles)
        }
    }
}

/// 待刪除項目單行顯示
struct DeletionQueueItem: View {
    let node: FileNode
    @ObservedObject var deletionService: FileDeletionService
    
    var body: some View {
        HStack {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(node.isDirectory ? .blue : .orange)
                .frame(width: 16)
            
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Text(node.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(action: {
                deletionService.removeFromDeletionQueue(node)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
}

#Preview {
    let deletionService = FileDeletionService()
    let scanner = FileSystemScanner(deletionService: deletionService)
    
    return DeletionZone(deletionService: deletionService, scanner: scanner)
}

import Foundation
import Combine

/// 檔案刪除服務，負責處理檔案刪除相關功能
class FileDeletionService: ObservableObject {
    @Published var deletionQueue: [FileNode] = []
    @Published var isDeletingFiles: Bool = false
    @Published var error: AppError?
    @Published var showDeletionConfirmation: Bool = false
    
    private let fileManager = FileManager.default
    
    /// 計算刪除隊列總大小
    var deletionQueueTotalSize: Int64 {
        return deletionQueue.reduce(0) { $0 + $1.size }
    }
    
    /// 添加檔案到刪除隊列
    func addToDeletionQueue(_ node: FileNode) {
        // 避免重複添加
        if !deletionQueue.contains(where: { $0.id == node.id }) {
            deletionQueue.append(node)
            print("📝 已添加到刪除隊列: \(node.name)")
        }
    }
    
    /// 從刪除隊列移除檔案
    func removeFromDeletionQueue(_ node: FileNode) {
        deletionQueue.removeAll { $0.id == node.id }
        print("❌ 已從刪除隊列移除: \(node.name)")
    }
    
    /// 清空刪除隊列
    func clearDeletionQueue() {
        deletionQueue.removeAll()
        print("🗑️ 已清空刪除隊列")
    }
    
    /// 執行批次刪除
    func executeFileDeletion(completion: @escaping ([String]) -> Void) {
        guard !deletionQueue.isEmpty else { return }
        
        isDeletingFiles = true
        error = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var successCount = 0
            var failedItems: [String] = []
            var firstError: Error?
            
            for node in self.deletionQueue {
                do {
                    try self.moveToTrash(url: node.url)
                    successCount += 1
                    print("✅ 已移動到垃圾桶: \(node.name)")
                } catch {
                    failedItems.append(node.name)
                    if firstError == nil {
                        firstError = error
                    }
                    print("❌ 刪除失敗: \(node.name) - \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.isDeletingFiles = false
                
                if failedItems.isEmpty {
                    self.error = nil
                    // 刪除成功，通知完成回調
                    completion([])
                    self.clearDeletionQueue()
                } else {
                    // 使用 DeletionError
                    if let firstError = firstError {
                        self.error = AppError.deletionError(.trashFailed(failedItems.first ?? "", firstError))
                    } else {
                        self.error = AppError.deletionError(.unknown(NSError(domain: "FileDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "刪除失敗"])))
                    }
                    completion(failedItems)
                }
            }
        }
    }
    
    /// 移動檔案到垃圾桶
    private func moveToTrash(url: URL) throws {
        var trashedURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
    }
}

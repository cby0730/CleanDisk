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
    /// - Parameter completion: 完成回調，傳遞成功刪除的節點陣列
    func executeFileDeletion(completion: @escaping (_ deletedNodes: [FileNode]) -> Void) {
        guard !deletionQueue.isEmpty else { return }
        
        isDeletingFiles = true
        error = nil
        
        // 在執行前複製佇列，避免並發問題
        let nodesToDelete = deletionQueue
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var successNodes: [FileNode] = []
            var failedNodes: [FileNode] = []
            var firstError: Error?
            
            for node in nodesToDelete {
                do {
                    try self.moveToTrash(url: node.url)
                    successNodes.append(node)
                    print("✅ 已移動到垃圾桶: \(node.name)")
                } catch {
                    failedNodes.append(node)
                    if firstError == nil {
                        firstError = error
                    }
                    print("❌ 刪除失敗: \(node.name) - \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.isDeletingFiles = false
                
                if failedNodes.isEmpty {
                    // 全部成功，清空佇列
                    self.error = nil
                    self.clearDeletionQueue()
                } else {
                    // 部分失敗，只保留失敗的項目在佇列中（讓用戶可以重試）
                    self.deletionQueue = failedNodes
                    
                    // 設置錯誤訊息
                    let failedNames = failedNodes.map { $0.name }
                    if let firstError = firstError {
                        self.error = AppError.deletionError(.trashFailed(failedNames.first ?? "", firstError))
                    } else {
                        self.error = AppError.deletionError(.unknown(NSError(domain: "FileDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "部分檔案刪除失敗"])))
                    }
                    
                    print("⚠️ 部分刪除失敗，保留 \(failedNodes.count) 個項目在佇列中")
                }
                
                // 回調傳遞成功刪除的節點
                completion(successNodes)
            }
        }
    }
    
    /// 移動檔案到垃圾桶
    private func moveToTrash(url: URL) throws {
        var trashedURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
    }
}

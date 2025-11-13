import Foundation
import Combine

/// 檔案系統掃描器，負責掃描指定路徑並建立檔案樹
class FileSystemScanner: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var scanProgress: ScanProgress = ScanProgress()
    @Published var rootNode: FileNode?
    @Published var selectedNode: FileNode?
    @Published var errorMessage: String?
    
    // 刪除服務
    @Published var deletionService = FileDeletionService()
    
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    
    /// 開始掃描指定路徑
    func startScan(at path: String) {
        guard !isScanning else { return }
        
        isScanning = true
        errorMessage = nil
        scanProgress = ScanProgress()
        
        let url = URL(fileURLWithPath: path)
        rootNode = FileNode(url: url)
        
        // 在背景執行緒進行掃描
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performScan()
        }
    }
    
    /// 執行實際的掃描作業
    private func performScan() {
        guard let rootNode = rootNode else { return }
        
        do {
            // 第一階段：計算總檔案數量以計算進度
            DispatchQueue.main.async {
                self.scanProgress.currentPath = "正在計算檔案總數..."
            }
            
            let totalCount = try countAllItems(at: rootNode.url)
            
            DispatchQueue.main.async {
                self.scanProgress.totalItems = totalCount
                self.scanProgress.currentPath = "開始掃描..."
                print("📊 總項目數量: \(totalCount)")
            }
            
            // 第二階段：實際掃描並計算大小
            let calculatedSize = try scanDirectory(node: rootNode)
            
            DispatchQueue.main.async {
                rootNode.size = calculatedSize
                rootNode.sortChildrenBySize()
                self.isScanning = false
                self.scanProgress.currentPath = "掃描完成"
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "掃描失敗: \(error.localizedDescription)"
                self.isScanning = false
            }
        }
    }
    
    /// 計算指定路徑下的所有項目數量
    private func countAllItems(at url: URL) throws -> Int {
        return try countItemsRecursively(at: url)
    }
    
    /// 遞歸計算項目數量，使用與掃描相同的邏輯
    private func countItemsRecursively(at url: URL) throws -> Int {
        return try autoreleasepool {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            
            do {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                // 跳過符號連結
                if resourceValues.isSymbolicLink == true {
                    return 0
                }
                
                // 計算當前項目
                var count = 1
                
                // 如果是目錄，遞歸計算子項目
                if resourceValues.isDirectory == true {
                    do {
                        let contents = try fileManager.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: resourceKeys,
                            options: [] // 預設會包含隱藏檔案
                        )
                        
                        for childURL in contents {
                            autoreleasepool {
                                do {
                                    let childCount = try countItemsRecursively(at: childURL)
                                    count += childCount
                                } catch {
                                    // 無法存取的檔案就跳過，與 scanDirectory 保持一致
                                }
                            }
                        }
                    } catch {
                        // 無法存取目錄內容，只計算目錄本身
                    }
                }
                
                return count
            } catch {
                // 無法存取的檔案就跳過
                return 0
            }
        }
    }
    
    /// 掃描資料夾並建立子節點
    private func scanDirectory(node: FileNode) throws -> Int64 {
        return try autoreleasepool {
            // 更新當前掃描路徑
            DispatchQueue.main.async {
                self.scanProgress.currentPath = node.url.path
            }
            
            guard node.isDirectory else {
                // 對於檔案，更新進度並取得大小
                DispatchQueue.main.async {
                    self.scanProgress.processedItems += 1
                }
                do {
                    let size = try getFileSize(at: node.url)
                    if size == 0 {
                        print("📄 檔案 \(node.url.lastPathComponent) 大小為 0")
                    }
                    return size
                } catch {
                    print("❌ 無法取得檔案 \(node.url.path) 大小: \(error)")
                    return 0
                }
            }
            
            var totalSize: Int64 = 0
            var childNodes: [FileNode] = []
            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]
            
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: node.url,
                    includingPropertiesForKeys: resourceKeys,
                    options: [] // 預設會包含隱藏檔案
                )
                
                for childURL in contents {
                    autoreleasepool {
                        do {
                            let resourceValues = try childURL.resourceValues(forKeys: Set(resourceKeys))
                            
                            // 跳過符號連結
                            if resourceValues.isSymbolicLink == true {
                                return
                            }
                            
                            let childNode = FileNode(url: childURL)
                            
                            if resourceValues.isDirectory == true {
                                // 遞迴掃描子資料夾
                                childNode.size = try scanDirectory(node: childNode)
                            } else {
                                // 遞迴掃描檔案
                                childNode.size = try scanDirectory(node: childNode)
                            }
                            
                            totalSize += childNode.size
                            childNodes.append(childNode)
                            
                        } catch {
                            // 無法存取的檔案就跳過
                            // 注意：這裡不更新進度，因為countAllItems在遇到錯誤時也會跳過
                        }
                    }
                }
                
                // 按大小排序子節點
                childNodes.sort { $0.size > $1.size }
                
                // 在主執行緒更新 UI
                DispatchQueue.main.async {
                    node.children = childNodes
                    // 目錄處理完畢，更新進度
                    self.scanProgress.processedItems += 1
                }
                
            } catch {
                // 無法存取資料夾內容，但資料夾本身可能有大小
                totalSize = try getFileSize(at: node.url)
                // 目錄處理完畢，更新進度
                DispatchQueue.main.async {
                    self.scanProgress.processedItems += 1
                }
            }
            
            return totalSize
        }
    }
    
    /// 取得檔案大小（最有效的方式）
    private func getFileSize(at url: URL, resourceValues: URLResourceValues? = nil) throws -> Int64 {
        let values: URLResourceValues
        
        if let resourceValues = resourceValues {
            values = resourceValues
        } else {
            do {
                values = try url.resourceValues(forKeys: [
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey
                ])
            } catch {
                // 如果無法取得 resourceValues，嘗試用 FileManager
                print("⚠️ 無法取得 resourceValues for \(url.path): \(error)")
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    if let size = attributes[.size] as? NSNumber {
                        print("✅ 使用 FileManager 取得 \(url.lastPathComponent) 大小: \(size.int64Value)")
                        return size.int64Value
                    }
                } catch {
                    print("❌ FileManager 也無法取得 \(url.path) 大小: \(error)")
                }
                return 0
            }
        }
        
        // 優先使用 totalFileAllocatedSize（包含稀疏檔案的實際佔用空間）
        if let totalAllocatedSize = values.totalFileAllocatedSize {
            return Int64(totalAllocatedSize)
        }
        
        // 其次使用 fileAllocatedSize
        if let allocatedSize = values.fileAllocatedSize {
            return Int64(allocatedSize)
        }
        
        // 最後使用 fileSize
        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }
        
        // 如果都無法取得，嘗試使用 FileManager
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                print("✅ 備用方法取得 \(url.lastPathComponent) 大小: \(size.int64Value)")
                return size.int64Value
            }
        } catch {
            print("❌ 所有方法都無法取得 \(url.path) 大小: \(error)")
        }
        
        print("⚠️ \(url.lastPathComponent) 大小為 0 或無法取得")
        return 0
    }
    
    // MARK: - 檔案樹更新功能
    
    /// 更新檔案樹，移除已刪除的項目
    func updateFileTreeAfterDeletion(deletedNodes: [FileNode]) {
        guard let rootNode = rootNode else { return }
        
        let deletedPaths = Set(deletedNodes.map { $0.url.path })
        removeDeletedNodes(from: rootNode, deletedPaths: deletedPaths)
        
        // 重新計算大小
        recalculateSizes(node: rootNode)
        
        print("🔄 檔案樹已更新，移除了 \(deletedPaths.count) 個項目")
    }
    
    /// 遞歸移除已刪除的節點
    private func removeDeletedNodes(from node: FileNode, deletedPaths: Set<String>) {
        node.children.removeAll { child in
            if deletedPaths.contains(child.url.path) {
                return true
            } else {
                // 遞歸檢查子項目
                removeDeletedNodes(from: child, deletedPaths: deletedPaths)
                return false
            }
        }
    }
    
    /// 重新計算節點大小
    private func recalculateSizes(node: FileNode) {
        if node.isDirectory {
            node.size = node.children.reduce(0) { total, child in
                recalculateSizes(node: child)
                return total + child.size
            }
            node.sortChildrenBySize()
        }
    }
}

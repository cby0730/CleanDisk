import Foundation
import Combine

/// 檔案系統掃描器，負責掃描指定路徑並建立檔案樹
class FileSystemScanner: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var scanProgress: ScanProgress = ScanProgress()
    @Published var rootNode: FileNode?
    @Published var selectedNode: FileNode?
    @Published var error: AppError?
    @Published var lastScanSummary: ScanSummary?
    @Published var wasLastResultCleared: Bool = false
    
    // 刪除服務（透過依賴注入）
    let deletionService: FileDeletionService
    
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    private var cancelRequested = false
    private var currentScanId: UUID?
    private var scanStartDate: Date?
    
    // 進度更新節流機制
    private var lastProgressUpdateTime = Date()
    private var pendingProcessedItems = 0
    private var pendingCurrentPath: String = ""
    private let progressUpdateInterval: TimeInterval = 0.1
    
    // MARK: - URL Cache (Thread-Safe)
    /// 用於保護快取的並發隊列（讀取並發，寫入獨佔）
    private let cacheQueue = DispatchQueue(label: "com.cleandisk.cache", attributes: .concurrent)
    /// URL 路徑到 FileNode 的快取字典
    private var _urlToNodeCache: [String: FileNode] = [:]

    /// 初始化掃描器
    /// - Parameter deletionService: 檔案刪除服務
    init(deletionService: FileDeletionService) {
        self.deletionService = deletionService
    }

    private func shouldContinue(scanId: UUID) -> Bool {
        return !cancelRequested && currentScanId == scanId
    }

    private func checkCancellation(scanId: UUID) throws {
        if !shouldContinue(scanId: scanId) {
            throw ScanError.cancelled
        }
    }
    
    /// 開始掃描指定路徑
    func startScan(at path: String) {
        guard !isScanning else { return }
        
        cancelRequested = false
        let scanId = UUID()
        currentScanId = scanId
        scanStartDate = Date()

        isScanning = true
        error = nil
        scanProgress = ScanProgress()
        wasLastResultCleared = false
        lastScanSummary = nil
        
        // 初始化節流變數
        lastProgressUpdateTime = Date()
        pendingProcessedItems = 0
        pendingCurrentPath = ""
        
        let url = URL(fileURLWithPath: path)
        rootNode = FileNode(url: url)
        
        // 在背景執行緒進行掃描
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performScan(scanId: scanId)
        }
    }

    /// 取消目前掃描
    func cancelScan() {
        guard isScanning else { return }

        cancelRequested = true
        currentScanId = nil
        clearCache()

        DispatchQueue.main.async {
            self.isScanning = false
            self.scanProgress.currentPath = "掃描已取消"
            self.error = nil
            self.rootNode = nil
            self.selectedNode = nil
            self.scanStartDate = nil
        }
    }

    /// 清除目前的掃描結果，釋放記憶體
    func clearScanResult() {
        guard !isScanning else { return }
        rootNode = nil
        selectedNode = nil
        scanProgress = ScanProgress()
        deletionService.clearDeletionQueue()
        wasLastResultCleared = lastScanSummary != nil
        clearCache()
    }
    
    // MARK: - URL Cache Methods
    
    /// 新增節點到快取（執行緒安全，使用 barrier 獨佔寫入）
    private func addToCache(_ node: FileNode) {
        let key = node.url.standardizedFileURL.path
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?._urlToNodeCache[key] = node
        }
    }
    
    /// 根據 URL 查找對應的 FileNode（O(1) 時間複雜度，執行緒安全）
    /// - Parameter url: 要查找的檔案 URL
    /// - Returns: 對應的 FileNode，若不存在則返回 nil
    func findNode(by url: URL) -> FileNode? {
        let key = url.standardizedFileURL.path
        return cacheQueue.sync {
            return _urlToNodeCache[key]
        }
    }
    
    /// 清空快取（執行緒安全，使用 barrier 獨佔寫入）
    private func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?._urlToNodeCache.removeAll()
        }
    }
    
    /// 執行實際的掃描作業
    private func performScan(scanId: UUID) {
        guard let rootNode = rootNode else { return }
        
        // 掃描開始時清空快取
        clearCache()
        
        // 將 rootNode 加入快取
        addToCache(rootNode)
        
        do {
            // 第一階段：計算總檔案數量以計算進度
            DispatchQueue.main.async {
                guard self.shouldContinue(scanId: scanId) else { return }
                self.scanProgress.currentPath = "正在計算檔案總數..."
            }
            
            try checkCancellation(scanId: scanId)

            let totalCount = try countAllItems(at: rootNode.url, scanId: scanId)
            
            DispatchQueue.main.async {
                guard self.shouldContinue(scanId: scanId) else { return }
                self.scanProgress.totalItems = totalCount
                self.scanProgress.currentPath = "開始掃描..."
                print("📊 總項目數量: \(totalCount)")
            }
            
            // 第二階段：實際掃描並計算大小
            try checkCancellation(scanId: scanId)

            let calculatedSize = try scanDirectory(node: rootNode, scanId: scanId)
            
            // 掃描結束前，強制更新最後一次進度
            updateProgressToMainThread(force: true, scanId: scanId)
            
            DispatchQueue.main.async {
                guard self.shouldContinue(scanId: scanId) else { return }
                rootNode.size = calculatedSize
                rootNode.sortChildrenBySize()
                self.isScanning = false
                self.scanProgress.currentPath = "掃描完成"
                let summary = ScanSummary(
                    path: rootNode.url.path,
                    totalItems: self.scanProgress.totalItems,
                    totalSize: calculatedSize,
                    startedAt: self.scanStartDate ?? Date(),
                    completedAt: Date()
                )
                self.lastScanSummary = summary
                self.currentScanId = nil
                self.scanStartDate = nil
            }
            
        } catch let error as ScanError where error == .cancelled {
            DispatchQueue.main.async {
                if self.scanProgress.currentPath != "掃描已取消" {
                    self.scanProgress.currentPath = "掃描已取消"
                }
                self.isScanning = false
                self.currentScanId = nil
                self.scanStartDate = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.error = AppError.scanError(.unknown(error))
                self.isScanning = false
                self.currentScanId = nil
                self.scanStartDate = nil
            }
        }
    }
    
    /// 計算指定路徑下的所有項目數量
    private func countAllItems(at url: URL, scanId: UUID) throws -> Int {
        try checkCancellation(scanId: scanId)
        return try countItemsRecursively(at: url, scanId: scanId)
    }
    
    /// 遞歸計算項目數量，使用與掃描相同的邏輯
    private func countItemsRecursively(at url: URL, scanId: UUID) throws -> Int {
        try checkCancellation(scanId: scanId)

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
                        try checkCancellation(scanId: scanId)
                        do {
                            let childCount = try countItemsRecursively(at: childURL, scanId: scanId)
                            count += childCount
                        } catch {
                            if let scanError = error as? ScanError, scanError == .cancelled {
                                throw scanError
                            }
                            // 無法存取的檔案就跳過，與 scanDirectory 保持一致
                        }
                    }
                } catch {
                    if let scanError = error as? ScanError, scanError == .cancelled {
                        throw scanError
                    }
                    // 無法存取目錄內容，只計算目錄本身
                }
            }
            
            return count
        } catch {
            if let scanError = error as? ScanError, scanError == .cancelled {
                throw scanError
            }
            // 無法存取的檔案就跳過
            return 0
        }
    }
    
    /// 掃描資料夾並建立子節點
    private func scanDirectory(node: FileNode, scanId: UUID) throws -> Int64 {
        try checkCancellation(scanId: scanId)

        // 累積進度更新（使用節流機制）
        pendingCurrentPath = node.url.path
        pendingProcessedItems += 1
        updateProgressToMainThread(force: false, scanId: scanId)

        guard node.isDirectory else {
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
                try checkCancellation(scanId: scanId)

                do {
                    let resourceValues = try childURL.resourceValues(forKeys: Set(resourceKeys))

                    if resourceValues.isSymbolicLink == true {
                        continue
                    }

                    let childNode = FileNode(url: childURL)
                    
                    // 將新節點加入快取
                    addToCache(childNode)

                    childNode.size = try scanDirectory(node: childNode, scanId: scanId)

                    totalSize += childNode.size
                    childNodes.append(childNode)

                } catch {
                    if let scanError = error as? ScanError, scanError == .cancelled {
                        throw scanError
                    }
                    // 無法存取的檔案就跳過
                }
            }

            childNodes.sort { $0.size > $1.size }

            DispatchQueue.main.async {
                guard self.shouldContinue(scanId: scanId) else { return }
                node.children = childNodes
            }

        } catch {
            if let scanError = error as? ScanError, scanError == .cancelled {
                throw scanError
            }
            totalSize = try getFileSize(at: node.url)
        }

        return totalSize
    }
    
    /// 節流更新進度到主執行緒
    /// - Parameters:
    ///   - force: 是否強制更新（忽略時間間隔）
    ///   - scanId: 當前掃描 ID
    private func updateProgressToMainThread(force: Bool, scanId: UUID) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastProgressUpdateTime) >= progressUpdateInterval
        
        guard shouldUpdate, pendingProcessedItems > 0 else { return }
        
        // 擷取當前累積的進度資訊
        let itemsToUpdate = pendingProcessedItems
        let pathToUpdate = pendingCurrentPath
        
        // 重置累積計數器
        pendingProcessedItems = 0
        lastProgressUpdateTime = now
        
        // 更新到主執行緒
        DispatchQueue.main.async {
            guard self.shouldContinue(scanId: scanId) else { return }
            self.scanProgress.processedItems += itemsToUpdate
            self.scanProgress.currentPath = pathToUpdate
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
    
    /// 更新檔案樹，移除已刪除的項目（在主執行緒異步執行）
    func updateFileTreeAfterDeletion(deletedNodes: [FileNode]) {
        guard let rootNode = rootNode else { return }
        
        let deletedPaths = Set(deletedNodes.map { $0.url.path })
        
        // 從快取中移除已刪除的節點
        for node in deletedNodes {
            removeFromCache(node)
        }
        
        // 在主執行緒異步執行（不阻塞當前操作，符合 SwiftUI 執行緒安全要求）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.removeDeletedNodes(from: rootNode, deletedPaths: deletedPaths)
            self.recalculateSizes(node: rootNode)
            
            print("🔄 檔案樹已更新，移除了 \(deletedPaths.count) 個項目")
        }
    }
    
    /// 從快取中移除節點（執行緒安全）
    private func removeFromCache(_ node: FileNode) {
        let key = node.url.standardizedFileURL.path
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?._urlToNodeCache.removeValue(forKey: key)
        }
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

/// 掃描摘要資訊
struct ScanSummary: Identifiable {
    let id = UUID()
    let path: String
    let totalItems: Int
    let totalSize: Int64
    let startedAt: Date
    let completedAt: Date
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var duration: TimeInterval {
        max(0, completedAt.timeIntervalSince(startedAt))
    }
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : (duration >= 60 ? [.minute, .second] : [.second])
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: duration) ?? String(format: "%.1f 秒", duration)
    }
    
    var formattedCompletedAt: String {
        DateFormatter.localizedString(from: completedAt, dateStyle: .medium, timeStyle: .short)
    }
}

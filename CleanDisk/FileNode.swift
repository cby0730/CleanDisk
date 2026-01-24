import Foundation

/// 檔案系統節點，代表一個檔案或資料夾
class FileNode: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    @Published var size: Int64 = 0
    @Published var children: [FileNode] = []
    @Published var isExpanded: Bool = false
    @Published var isLoaded: Bool = false
    
    /// 格式化的檔案大小字串
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// 檔案或資料夾的圖示名稱
    var iconName: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        } else {
            return "doc"
        }
    }
    
    /// 檔案類型描述
    var fileType: String {
        if isDirectory {
            return "資料夾"
        }
        
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return "檔案"
        }
        return "\(ext.uppercased()) 檔案"
    }
    
    /// 最後修改時間
    var modificationDate: Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
    
    /// 用於拖拉操作的項目提供者
    var itemProvider: NSItemProvider {
        // 使用 URL 作為拖放對象，確保所有檔案類型都能正確處理
        // NSItemProvider(contentsOf:) 會根據檔案內容類型返回不同 UTI，
        // 可能導致某些檔案類型（如 PDF）無法被識別為 public.file-url
        let provider = NSItemProvider(object: url as NSURL)
        return provider
    }
    
    /// 文件擴展名
    var fileExtension: String {
        return url.pathExtension.lowercased()
    }
    
    /// 是否為隱藏文件
    var isHidden: Bool {
        return name.hasPrefix(".")
    }
    
    /// 最後存取時間
    var lastAccessDate: Date? {
        do {
            let values = try url.resourceValues(forKeys: [.contentAccessDateKey])
            return values.contentAccessDate
        } catch {
            return nil
        }
    }
    
    /// 檔案是否被鎖定
    var isLocked: Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isUserImmutableKey])
            return values.isUserImmutable ?? false
        } catch {
            return false
        }
    }
    
    /// 父資料夾名稱（提供上下文）
    var parentFolderName: String {
        return url.deletingLastPathComponent().lastPathComponent
    }
    
    /// 是否位於快取目錄中
    var isInCachesDir: Bool {
        let path = url.path
        return path.contains("/Caches/") || path.contains("/Cache/")
    }
    
    /// 是否位於暫存目錄中
    var isInTempDir: Bool {
        let path = url.path
        return path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") ||
               path.contains("/Temp/") || path.contains("/tmp/")
    }
    
    /// 距離最後修改的天數
    var daysSinceModified: Int? {
        guard let modDate = modificationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: modDate, to: Date()).day
    }
    
    /// 文件深度（用於樹狀顯示）
    var depth: Int = 0
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        // 檢查是否為資料夾
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            self.isDirectory = isDir.boolValue
        } else {
            self.isDirectory = false
        }
    }
    
    /// 切換展開狀態
    func toggleExpansion() {
        isExpanded.toggle()
    }
    
    /// 按大小排序子項目（大到小）
    func sortChildrenBySize() {
        children.sort { $0.size > $1.size }
    }
    
    /// 按名稱排序子項目（字母順序）
    func sortChildrenByName() {
        children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// 按修改時間排序子項目（最新到最舊）
    func sortChildrenByModificationDate() {
        children.sort { 
            guard let date1 = $0.modificationDate, let date2 = $1.modificationDate else {
                return false
            }
            return date1 > date2
        }
    }
    
    /// 搜尋子項目（使用迭代方式避免深層目錄堆疊溢出）
    /// - Parameters:
    ///   - query: 搜尋關鍵字
    ///   - maxDepth: 最大搜尋深度，nil 表示不限制（預設）
    /// - Returns: 符合條件的節點陣列
    func searchChildren(query: String, maxDepth: Int? = nil) -> [FileNode] {
        guard !query.isEmpty else { return children }
        
        var results: [FileNode] = []
        
        // 使用堆疊進行迭代式深度優先搜尋，避免遞迴導致的堆疊溢出
        // 堆疊元素為 (節點, 當前深度)
        var stack: [(node: FileNode, depth: Int)] = children.map { ($0, 1) }
        
        while !stack.isEmpty {
            let (currentNode, currentDepth) = stack.removeLast()
            
            // 檢查是否符合搜尋條件
            if currentNode.name.localizedCaseInsensitiveContains(query) {
                results.append(currentNode)
            }
            
            // 如果是目錄且未超過深度限制，將子節點加入堆疊
            if currentNode.isDirectory {
                let shouldContinue = maxDepth == nil || currentDepth < maxDepth!
                if shouldContinue {
                    // 反向加入以保持順序（因為堆疊是 LIFO）
                    for child in currentNode.children.reversed() {
                        stack.append((child, currentDepth + 1))
                    }
                }
            }
        }
        
        return results
    }
    
    /// 計算總項目數（使用迭代方式避免堆疊溢出）
    var totalItemCount: Int {
        var count = 1 // 包含自己
        var stack = children
        
        while !stack.isEmpty {
            let current = stack.removeLast()
            count += 1
            // 只有目錄才需要遍歷子項目（保持與 fileCount、directoryCount 一致）
            if current.isDirectory {
                stack.append(contentsOf: current.children)
            }
        }
        
        return count
    }
    
    /// 計算檔案數量（使用迭代方式避免堆疊溢出）
    var fileCount: Int {
        if !isDirectory {
            return 1
        }
        
        var count = 0
        var stack = children
        
        while !stack.isEmpty {
            let current = stack.removeLast()
            if current.isDirectory {
                stack.append(contentsOf: current.children)
            } else {
                count += 1
            }
        }
        
        return count
    }
    
    /// 計算目錄數量（使用迭代方式避免堆疊溢出）
    var directoryCount: Int {
        if !isDirectory {
            return 0
        }
        
        var count = 1 // 包含自己
        var stack = children
        
        while !stack.isEmpty {
            let current = stack.removeLast()
            if current.isDirectory {
                count += 1
                stack.append(contentsOf: current.children)
            }
        }
        
        return count
    }
}

/// 掃描進度資訊
struct ScanProgress {
    var totalItems: Int = 0
    var processedItems: Int = 0
    var currentPath: String = ""
    
    var percentage: Double {
        guard totalItems > 0 else { return 0.0 }
        let rawPercentage = Double(processedItems) / Double(totalItems) * 100.0
        // 確保百分比在 0-100 範圍內，防止 ProgressView 警告
        return min(100.0, max(0.0, rawPercentage))
    }
    
    var isComplete: Bool {
        return totalItems > 0 && processedItems >= totalItems
    }
}

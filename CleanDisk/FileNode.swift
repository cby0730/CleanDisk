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
        let provider = NSItemProvider()
        
        // 直接註冊 URL，而不是使用 bookmark data
        provider.registerObject(url as NSURL, visibility: .all)
        
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
    
    /// 搜尋子項目
    func searchChildren(query: String) -> [FileNode] {
        guard !query.isEmpty else { return children }
        
        var results: [FileNode] = []
        
        // 搜尋當前層級
        for child in children {
            if child.name.localizedCaseInsensitiveContains(query) {
                results.append(child)
            }
            
            // 遞歸搜尋子目錄
            if child.isDirectory {
                results.append(contentsOf: child.searchChildren(query: query))
            }
        }
        
        return results
    }
    
    /// 計算總項目數
    var totalItemCount: Int {
        var count = 1 // 包含自己
        
        for child in children {
            count += child.totalItemCount
        }
        
        return count
    }
    
    /// 計算檔案數量
    var fileCount: Int {
        if !isDirectory {
            return 1
        }
        
        var count = 0
        for child in children {
            count += child.fileCount
        }
        
        return count
    }
    
    /// 計算目錄數量
    var directoryCount: Int {
        if !isDirectory {
            return 0
        }
        
        var count = 1 // 包含自己
        for child in children {
            count += child.directoryCount
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

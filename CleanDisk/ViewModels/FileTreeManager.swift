import Foundation

/// 排序選項枚舉
enum SortOption: String, CaseIterable {
    case name = "名稱"
    case size = "大小"
    case modificationDate = "修改時間"
    case type = "類型"
    
    var systemImageName: String {
        switch self {
        case .name:
            return "textformat.abc"
        case .size:
            return "chart.bar"
        case .modificationDate:
            return "clock"
        case .type:
            return "doc.badge.gearshape"
        }
    }
}

/// 檔案樹管理器，負責文件樹的操作和管理
class FileTreeManager: ObservableObject {
    @Published var sortOption: SortOption = .size
    @Published var showHiddenFiles: Bool = false
    @Published var searchQuery: String = ""
    
    /// 根據當前設置對節點進行排序
    func sortNode(_ node: FileNode) {
        switch sortOption {
        case .name:
            node.sortChildrenByName()
        case .size:
            node.sortChildrenBySize()
        case .modificationDate:
            node.sortChildrenByModificationDate()
        case .type:
            node.sortChildrenByType()
        }
        
        // 遞歸排序子節點
        for child in node.children {
            sortNode(child)
        }
    }
    
    /// 過濾節點（基於隱藏文件設置和搜索查詢）
    func filteredChildren(of node: FileNode) -> [FileNode] {
        var filtered = node.children
        
        // 過濾隱藏文件
        if !showHiddenFiles {
            filtered = filtered.filter { !$0.isHidden }
        }
        
        // 搜索過濾
        if !searchQuery.isEmpty {
            filtered = filtered.filter { child in
                child.name.localizedCaseInsensitiveContains(searchQuery) ||
                child.searchChildren(query: searchQuery).count > 0
            }
        }
        
        return filtered
    }
}

extension FileNode {
    /// 按類型排序子項目
    func sortChildrenByType() {
        children.sort { node1, node2 in
            // 目錄排在前面
            if node1.isDirectory && !node2.isDirectory {
                return true
            } else if !node1.isDirectory && node2.isDirectory {
                return false
            }
            
            // 同類型按擴展名排序
            if !node1.isDirectory && !node2.isDirectory {
                let ext1 = node1.fileExtension
                let ext2 = node2.fileExtension
                if ext1 != ext2 {
                    return ext1.localizedCaseInsensitiveCompare(ext2) == .orderedAscending
                }
            }
            
            // 最後按名稱排序
            return node1.name.localizedCaseInsensitiveCompare(node2.name) == .orderedAscending
        }
    }
}

import SwiftUI

/// 檔案樹狀顯示視圖
struct FileTreeView: View {
    @ObservedObject var node: FileNode
    @EnvironmentObject var scanner: FileSystemScanner
    @State private var isExpanded: Bool = true
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜尋列
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜尋檔案或資料夾...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                if !searchText.isEmpty {
                    Button("清除") {
                        searchText = ""
                    }
                    .font(.caption)
                }
            }
            .padding()
            
            Divider()
            
            // 工具列
            FileTreeToolbar()
            
            // 檔案樹
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    FileNodeRow(
                        node: node, 
                        level: 0, 
                        isExpanded: $isExpanded,
                        searchText: searchText,
                        maxSize: node.size
                    )
                    
                    if isExpanded && node.isDirectory {
                        ForEach(node.children) { child in
                            FileNodeSubTree(
                                node: child, 
                                level: 1,
                                searchText: searchText,
                                maxSize: node.size
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("CleanDisk")
    }
}

/// 檔案樹工具列
struct FileTreeToolbar: View {
    var body: some View {
        HStack {
            Text("檔案系統")
                .font(.headline)
            Spacer()
            Text("大小")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }
}

/// 檔案節點子樹（遞迴顯示）
struct FileNodeSubTree: View {
    @ObservedObject var node: FileNode
    @EnvironmentObject var scanner: FileSystemScanner
    let level: Int
    let searchText: String
    let maxSize: Int64
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            FileNodeRow(
                node: node, 
                level: level, 
                isExpanded: $isExpanded,
                searchText: searchText,
                maxSize: maxSize
            )
            
            if isExpanded && node.isDirectory {
                ForEach(node.children) { child in
                    FileNodeSubTree(
                        node: child, 
                        level: level + 1,
                        searchText: searchText,
                        maxSize: maxSize
                    )
                }
            }
        }
    }
}

#Preview {
    let sampleNode = FileNode(url: URL(fileURLWithPath: "/"))
    let deletionService = FileDeletionService()
    let scanner = FileSystemScanner(deletionService: deletionService)
    return FileTreeView(node: sampleNode)
        .environmentObject(scanner)
}

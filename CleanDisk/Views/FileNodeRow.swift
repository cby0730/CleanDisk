import SwiftUI

/// 檔案節點行顯示
struct FileNodeRow: View {
    @ObservedObject var node: FileNode
    @EnvironmentObject var scanner: FileSystemScanner
    let level: Int
    @Binding var isExpanded: Bool
    let searchText: String
    let maxSize: Int64
    
    private var isSelected: Bool {
        scanner.selectedNode?.id == node.id
    }
    
    private var isHighlighted: Bool {
        !searchText.isEmpty && node.name.localizedCaseInsensitiveContains(searchText)
    }
    
    private var sizeRatio: Double {
        guard maxSize > 0 else { return 0 }
        return Double(node.size) / Double(maxSize)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 縮排線條
            if level > 0 {
                FileNodeIndentationLines(level: level)
            }
            
            // 展開/收合按鈕
            FileNodeExpandButton(node: node, isExpanded: $isExpanded)
            
            // 檔案圖示
            FileNodeIcon(node: node)
            
            // 檔案名稱
            FileNodeName(node: node, isHighlighted: isHighlighted)
            
            Spacer()
            
            // 大小視覺化條和百分比（根目錄不顯示）
            if node.size > 0 && level > 0 {
                FileNodeSizeVisualization(sizeRatio: sizeRatio)
            }
            
            // 檔案大小
            FileNodeSizeText(node: node)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onDrag {
            node.itemProvider
        }
        .onTapGesture {
            scanner.selectedNode = node
        }
        .contextMenu {
            FileNodeContextMenu(node: node)
        }
    }
}

// MARK: - 子組件

/// 檔案節點縮排線條
struct FileNodeIndentationLines: View {
    let level: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<level, id: \.self) { _ in
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)
                    .padding(.horizontal, 9)
            }
        }
        .frame(width: CGFloat(level * 20))
    }
}

/// 檔案節點展開按鈕
struct FileNodeExpandButton: View {
    let node: FileNode
    @Binding var isExpanded: Bool
    
    var body: some View {
        Group {
            if node.isDirectory && !node.children.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

/// 檔案節點圖示
struct FileNodeIcon: View {
    let node: FileNode
    
    var body: some View {
        Image(systemName: FileIconHelper.getIcon(for: node))
            .foregroundColor(FileIconHelper.getColor(for: node))
            .frame(width: 16)
    }
}

/// 檔案節點名稱
struct FileNodeName: View {
    let node: FileNode
    let isHighlighted: Bool
    
    var body: some View {
        Text(node.name)
            .lineLimit(1)
            .truncationMode(.middle)
            .background(isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
            .cornerRadius(4)
    }
}

/// 檔案節點大小視覺化
struct FileNodeSizeVisualization: View {
    let sizeRatio: Double
    
    var body: some View {
        HStack(spacing: 4) {
            // 大小條形圖
            RoundedRectangle(cornerRadius: 2)
                .fill(getSizeColor())
                .frame(width: CGFloat(sizeRatio * 60), height: 4)
                .opacity(0.7)
            
            // 百分比顯示
            Text(getPercentageText())
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(minWidth: 35, alignment: .trailing)
        }
    }
    
    private func getSizeColor() -> Color {
        if sizeRatio > 0.5 {
            return .red
        } else if sizeRatio > 0.2 {
            return .orange
        } else if sizeRatio > 0.05 {
            return .blue
        } else {
            return .green
        }
    }
    
    private func getPercentageText() -> String {
        let percentage = sizeRatio * 100
        
        if percentage < 0.1 {
            return "<0.1%"
        } else if percentage < 1.0 {
            return String(format: "%.1f%%", percentage)
        } else if percentage < 10.0 {
            return String(format: "%.1f%%", percentage)
        } else {
            return String(format: "%.0f%%", percentage)
        }
    }
}

/// 檔案節點大小文字
struct FileNodeSizeText: View {
    let node: FileNode
    
    var body: some View {
        Text(node.formattedSize)
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
            .frame(minWidth: 60, alignment: .trailing)
    }
}

/// 檔案節點右鍵選單
struct FileNodeContextMenu: View {
    let node: FileNode
    
    var body: some View {
        Button("在 Finder 中顯示") {
            NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: "")
        }
        
        if node.isDirectory {
            Button("展開全部") {
                expandAll(node: node)
            }
            Button("收合全部") {
                collapseAll(node: node)
            }
        }
        
        Button("複製路徑") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
    }
    
    private func expandAll(node: FileNode) {
        node.isExpanded = true
        for child in node.children {
            expandAll(node: child)
        }
    }
    
    private func collapseAll(node: FileNode) {
        node.isExpanded = false
        for child in node.children {
            collapseAll(node: child)
        }
    }
}

#Preview {
    let sampleNode = FileNode(url: URL(fileURLWithPath: "/Applications"))
    sampleNode.size = 1024 * 1024 * 100 // 100MB
    
    return FileNodeRow(
        node: sampleNode,
        level: 0,
        isExpanded: .constant(true),
        searchText: "",
        maxSize: 1024 * 1024 * 1000 // 1GB
    )
    .environmentObject(FileSystemScanner())
}

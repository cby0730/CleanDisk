import SwiftUI

/// 詳細資訊面板
struct DetailPanel: View {
    let selectedNode: FileNode?
    @EnvironmentObject var llmService: LLMService
    
    @State private var aiSuggestion: FileDeletionSuggestion?
    @State private var showingSuggestion: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題
            DetailPanelHeader()
            
            if let node = selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 基本資訊
                        DetailPanelBasicInfo(node: node)
                        
                        // AI 建議區塊（僅對檔案顯示）
                        if !node.isDirectory {
                            Divider()
                            DetailPanelAISuggestion(
                                node: node,
                                aiSuggestion: $aiSuggestion,
                                showingSuggestion: $showingSuggestion
                            )
                        }
                        
                        Divider()
                        
                        // 目錄統計（僅對資料夾）
                        if node.isDirectory {
                            DetailPanelDirectoryStats(node: node)
                            
                            Divider()
                            
                            // 最大檔案
                            if let largestFile = node.children.max(by: { $0.size < $1.size }) {
                                DetailPanelLargestItem(item: largestFile)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
                .onChange(of: node.id) { oldValue, newValue in
                    // 當選擇的檔案改變時，重置 AI 建議狀態
                    aiSuggestion = nil
                    showingSuggestion = false
                }
            } else {
                DetailPanelEmptyState()
            }
        }
    }
}

/// 詳細資訊面板標題
struct DetailPanelHeader: View {
    var body: some View {
        HStack {
            Text("詳細資訊")
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}

/// 詳細資訊面板基本資訊
struct DetailPanelBasicInfo: View {
    let node: FileNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基本資訊")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            DetailRow(label: "名稱", value: node.name)
            DetailRow(label: "類型", value: node.fileType)
            DetailRow(label: "大小", value: node.formattedSize)
            DetailRow(label: "路徑", value: node.url.path)
                .lineLimit(3)
            
            if let modDate = node.modificationDate {
                DetailRow(
                    label: "修改時間", 
                    value: DateFormatter.localizedString(from: modDate, dateStyle: .medium, timeStyle: .short)
                )
            }
        }
    }
}

/// 詳細資訊面板目錄統計
struct DetailPanelDirectoryStats: View {
    let node: FileNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目錄統計")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            DetailRow(label: "項目數量", value: "\(node.children.count)")
            
            let fileCount = node.children.filter { !$0.isDirectory }.count
            let dirCount = node.children.filter { $0.isDirectory }.count
            
            DetailRow(label: "檔案", value: "\(fileCount)")
            DetailRow(label: "資料夾", value: "\(dirCount)")
        }
    }
}

/// 詳細資訊面板最大項目
struct DetailPanelLargestItem: View {
    let item: FileNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最大項目")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: item.isDirectory ? "folder" : "doc")
                    .foregroundColor(item.isDirectory ? .blue : .primary)
                VStack(alignment: .leading) {
                    Text(item.name)
                        .lineLimit(2)
                    Text(item.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// 詳細資訊面板空狀態
struct DetailPanelEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("選擇項目以查看詳細資訊")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 詳細資訊行
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// AI 刪除建議區塊
struct DetailPanelAISuggestion: View {
    let node: FileNode
    @EnvironmentObject var llmService: LLMService
    
    @Binding var aiSuggestion: FileDeletionSuggestion?
    @Binding var showingSuggestion: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI 刪除建議")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 模型狀態指示
                if !llmService.isModelLoaded {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                        Text("載入模型中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 模型選擇器
            HStack {
                Text("模型:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("選擇模型", selection: $llmService.selectedModel) {
                    ForEach(LLMModel.allCases) { model in
                        HStack {
                            Text(model.displayName)
                            Text("(\(model.estimatedSize))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(llmService.isGenerating)
            }
            .padding(.vertical, 4)
            
            // 按鈕或載入狀態
            if llmService.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                    Text(llmService.loadingProgress)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if showingSuggestion, let suggestion = aiSuggestion {
                // 顯示建議結果
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(suggestion.icon)
                            .font(.title2)
                        Text(suggestion.recommendation)
                            .font(.headline)
                            .foregroundColor(suggestion.shouldDelete ? .red : .green)
                    }
                    
                    DetailRow(label: "信心度", value: suggestion.confidence.rawValue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("原因")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(suggestion.reasoning)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // 重新分析按鈕
                    Button("重新分析") {
                        Task {
                            await askAI()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                // 詢問 AI 按鈕
                Button(action: {
                    Task {
                        await askAI()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("詢問 AI 建議")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!llmService.isModelLoaded)
            }
            
            // 錯誤訊息
            if let error = llmService.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }
        }
        .onChange(of: llmService.selectedModel) { oldValue, newValue in
            // 當模型改變時，清空舊的 AI 建議
            aiSuggestion = nil
            showingSuggestion = false
        }
    }
    
    private func askAI() async {
        do {
            let suggestion = try await llmService.getSuggestion(for: node)
            await MainActor.run {
                self.aiSuggestion = suggestion
                self.showingSuggestion = true
            }
        } catch {
            print("❌ AI 建議生成失敗: \(error)")
        }
    }
}

#Preview {
    let sampleNode = FileNode(url: URL(fileURLWithPath: "/Applications"))
    sampleNode.size = 1024 * 1024 * 100 // 100MB
    
    return DetailPanel(selectedNode: sampleNode)
}

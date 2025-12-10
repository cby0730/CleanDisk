import SwiftUI

/// 側邊欄控制面板
struct SidebarControlPanel: View {
    @ObservedObject var scanner: FileSystemScanner
    @Binding var selectedPath: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 應用程式標題
            SidebarHeader()
            
            // 路徑選擇區域
            SidebarPathSelection(selectedPath: $selectedPath, scanner: scanner)
            
            // 掃描進度顯示
            if scanner.isScanning {
                SidebarScanProgress(scanner: scanner)
            }
            
            // 掃描完成摘要與清除動作
            if !scanner.isScanning, let summary = scanner.lastScanSummary {
                SidebarScanSummaryCard(scanner: scanner, summary: summary)
            }

            // 錯誤訊息顯示
            SidebarErrorMessages(scanner: scanner)
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)
    }
}

/// 側邊欄標題
struct SidebarHeader: View {
    var body: some View {
        Group {
            Text("CleanDisk")
                .font(.title)
                .fontWeight(.bold)
            
            Text("磁碟空間分析工具")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom)
    }
}

/// 側邊欄路徑選擇
struct SidebarPathSelection: View {
    @Binding var selectedPath: String
    @ObservedObject var scanner: FileSystemScanner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("掃描路徑:")
                .font(.headline)
            
            HStack {
                TextField("路徑", text: $selectedPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onAppear {
                        if selectedPath.isEmpty {
                            selectedPath = "/"
                        }
                    }
                
                Button("選擇") {
                    selectFolder()
                }
                .disabled(scanner.isScanning)
            }
            
            Button(action: { startScan() }) {
                HStack {
                    if scanner.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                        Text("掃描中...")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("開始掃描")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanner.isScanning || selectedPath.isEmpty)

            if scanner.isScanning {
                Button(action: {
                    scanner.cancelScan()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("停止掃描")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

        }
    }
    
    private func startScan() {
        scanner.startScan(at: selectedPath)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedPath = url.path
            }
        }
    }
}

/// 側邊欄掃描進度
struct SidebarScanProgress: View {
    @ObservedObject var scanner: FileSystemScanner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("掃描進度")
                .font(.headline)
            
            ProgressView(value: scanner.scanProgress.percentage, total: 100) {
                Text("\(Int(scanner.scanProgress.percentage))%")
                    .font(.caption)
            }
            
            Text(scanner.scanProgress.currentPath)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            
            Text("\(scanner.scanProgress.processedItems) / \(scanner.scanProgress.totalItems) 項目")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

/// 側邊欄錯誤訊息
struct SidebarErrorMessages: View {
    @ObservedObject var scanner: FileSystemScanner
    
    var body: some View {
        VStack(spacing: 8) {
            // 掃描錯誤訊息
            if let error = scanner.error {
                ErrorMessageView(error: error, color: .red)
            }
            
            // 刪除錯誤訊息
            if let error = scanner.deletionService.error {
                ErrorMessageView(error: error, color: .red)
            }
            
            // 刪除進度
            if scanner.deletionService.isDeletingFiles {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在刪除檔案...")
                        .font(.caption)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

/// 錯誤訊息視圖
struct ErrorMessageView: View {
    let error: AppError
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let description = error.errorDescription {
                Text(description)
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

/// 掃描完成後的摘要卡片
struct SidebarScanSummaryCard: View {
    @ObservedObject var scanner: FileSystemScanner
    let summary: ScanSummary
    @State private var showClearConfirmation = false
    
    private var formattedItemCount: String {
        NumberFormatter.localizedString(from: NSNumber(value: summary.totalItems), number: .decimal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("掃描完成", systemImage: "checkmark.seal")
                    .font(.headline)
                Spacer()
                Text(summary.formattedCompletedAt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    SummaryStat(label: "總大小", value: summary.formattedTotalSize)
                    Spacer()
                    SummaryStat(label: "項目", value: formattedItemCount)
                    Spacer()
                    SummaryStat(label: "耗時", value: summary.formattedDuration)
                }
            }

            if scanner.rootNode != nil {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清除目前掃描結果")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.isScanning)
                
                Text("清除後可釋放當前掃描使用的記憶體。之後仍可重新掃描該路徑。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if scanner.wasLastResultCleared {
                Label("掃描結果已清除", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .confirmationDialog(
            "確定要清除目前掃描結果嗎？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除並釋放記憶體", role: .destructive) {
                scanner.clearScanResult()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("此動作會移除當前掃描樹狀結果，但保留摘要資訊以供參考。")
        }
    }
}

/// 摘要統計欄位
private struct SummaryStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    let deletionService = FileDeletionService()
    let scanner = FileSystemScanner(deletionService: deletionService)
    return SidebarControlPanel(
        scanner: scanner,
        selectedPath: .constant("/")
    )
}

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
            if let errorMessage = scanner.errorMessage {
                ErrorMessageView(message: errorMessage, color: .red)
            }
            
            // 刪除錯誤訊息
            if let deletionError = scanner.deletionService.deletionError {
                ErrorMessageView(message: deletionError, color: .red)
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
    let message: String
    let color: Color
    
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(color)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(8)
    }
}

#Preview {
    SidebarControlPanel(
        scanner: FileSystemScanner(),
        selectedPath: .constant("/")
    )
}

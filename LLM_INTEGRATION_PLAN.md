# CleanDisk 本地 LLM 整合實作計劃

## 專案目標

在 CleanDisk 中整合本地小型 LLM，為使用者提供檔案刪除安全性分析，完全在本地執行以保護隱私。

## 技術選型

### 方案比較

| 方案 | 優點 | 缺點 | 推薦度 |
|------|------|------|--------|
| **MLX Swift** | • Apple 官方支援<br>• 原生 Swift API<br>• 針對 Apple Silicon 優化<br>• 活躍開發 | • 相對較新<br>• 文檔較少 | ⭐⭐⭐⭐⭐ |
| **llama.cpp + Swift** | • 成熟穩定<br>• 社群支援好<br>• 多個 Swift 套件可選 | • C++ 互操作<br>• 稍複雜 | ⭐⭐⭐⭐ |

### 🎯 推薦方案：**MLX Swift**

**理由**：
1. Apple 官方項目，長期支援有保障
2. 純 Swift API，與專案整合更自然
3. 針對 Apple Silicon 深度優化
4. 2024 年持續活躍開發

### 模型選擇

| 模型 | 大小 | 中文支援 | 用途 | 推薦度 |
|------|------|---------|------|--------|
| **Qwen2.5-3B-Instruct** (4-bit) | ~2GB | ⭐⭐⭐⭐⭐ | 檔案分析 | ⭐⭐⭐⭐⭐ |
| Phi-3.5-mini-instruct (4-bit) | ~2.3GB | ⭐⭐⭐ | 檔案分析 | ⭐⭐⭐⭐ |
| Llama-3.2-3B-Instruct (4-bit) | ~2GB | ⭐⭐⭐ | 檔案分析 | ⭐⭐⭐⭐ |

**最終選擇**：**Qwen2.5-3B-Instruct (4-bit 量化)**
- MLX 官方已提供轉換好的版本
- 優秀的中文理解能力
- 適中的模型大小（~2GB）
- 在 M1/M2/M3 上可流暢推理

## 實作架構

### 新增檔案結構

```
CleanDisk/
├── CleanDisk/
│   ├── Services/
│   │   ├── FileDeletionService.swift
│   │   ├── FileSystemScanner.swift
│   │   └── LLMService.swift              # 新增：LLM 服務
│   │
│   ├── Models/
│   │   ├── FileNode.swift
│   │   └── AIAnalysis.swift              # 新增：AI 分析結果模型
│   │
│   ├── Views/
│   │   ├── DetailPanel.swift             # 修改：加入 AI 按鈕
│   │   └── AIAnalysisSheet.swift         # 新增：AI 分析結果視圖
│   │
│   └── Resources/
│       └── Models/                        # 新增：模型檔案目錄
│           └── qwen2.5-3b-instruct-q4/
│
└── Package.swift                          # 新增：SPM 依賴
```

### 架構層級

```
┌─────────────────────────────────────────┐
│          UI Layer (SwiftUI)              │
│  DetailPanel + AIAnalysisSheet           │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         Service Layer                    │
│  LLMService (封裝 MLX 推理邏輯)         │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         MLX Swift Framework              │
│  (模型載入、推理、記憶體管理)           │
└──────────────────────────────────────────┘
```

## 實作步驟

### Phase 1: 環境設置 (2-3 天)

#### 1.1 新增 MLX Swift 依賴

```swift
// Package.swift
let package = Package(
    name: "CleanDisk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.15.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "CleanDisk",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples")
            ]
        )
    ]
)
```

#### 1.2 下載並整合模型

```bash
# 下載 Qwen2.5-3B-Instruct MLX 版本
cd CleanDisk/Resources/Models
huggingface-cli download mlx-community/Qwen2.5-3B-Instruct-4bit \
    --local-dir qwen2.5-3b-instruct-q4
```

**檔案大小管理**：
- 模型不應包含在 Git 倉庫中
- 在 `.gitignore` 加入 `Resources/Models/`
- 提供下載腳本供使用者首次設置

### Phase 2: LLM Service 實作 (3-4 天)

#### 2.1 資料模型定義

```swift
// Models/AIAnalysis.swift
import Foundation

struct AIAnalysis: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let safetyLevel: SafetyLevel
    let explanation: String
    let recommendation: String
    let recoveryHint: String?
    let timestamp: Date
    
    enum SafetyLevel: String, CaseIterable {
        case safe = "安全"           // 綠色：可安全刪除
        case caution = "謹慎"        // 黃色：建議保留或謹慎刪除
        case danger = "危險"         // 紅色：不建議刪除
        case unknown = "無法判斷"    // 灰色：資訊不足
        
        var color: Color {
            switch self {
            case .safe: return .green
            case .caution: return .orange
            case .danger: return .red
            case .unknown: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .safe: return "checkmark.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .danger: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }
    }
}

struct FileAnalysisContext {
    let fileName: String
    let fileExtension: String
    let fileType: String
    let size: Int64
    let formattedSize: String
    let sanitizedPath: String
    let parentFolder: String
    let modificationDate: Date?
    let isDirectory: Bool
    let fileCount: Int?
    let directoryCount: Int?
    
    // 自動偵測特徵
    var isSystemPath: Bool {
        sanitizedPath.hasPrefix("/System") ||
        sanitizedPath.hasPrefix("/Library") ||
        sanitizedPath.hasPrefix("/private")
    }
    
    var detectedPurpose: String? {
        if fileName == "node_modules" { return "npm 依賴套件" }
        if fileName == ".git" { return "Git 版本控制" }
        if fileName.hasPrefix("Pods") { return "CocoaPods 依賴" }
        if fileName == "DerivedData" { return "Xcode 建置產物" }
        if fileName == "build" { return "建置輸出目錄" }
        if fileExtension == "dmg" { return "磁碟映像檔" }
        if fileExtension == "log" { return "日誌檔案" }
        return nil
    }
}
```

#### 2.2 LLM Service 核心實作

```swift
// Services/LLMService.swift
import Foundation
import MLX
import MLXLLM

@MainActor
class LLMService: ObservableObject {
    @Published var isLoading = false
    @Published var isModelLoaded = false
    @Published var errorMessage: String?
    @Published var loadingProgress: Double = 0.0
    
    private var model: LLMModel?
    private let modelPath: String
    private let maxTokens = 512
    
    init(modelPath: String = "Resources/Models/qwen2.5-3b-instruct-q4") {
        self.modelPath = modelPath
    }
    
    // MARK: - Model Management
    
    func loadModel() async throws {
        guard !isModelLoaded else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 載入模型配置和權重
            let configuration = try await LLMModelConfiguration.load(from: modelPath)
            model = try await LLMModel.load(configuration: configuration) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress
                }
            }
            isModelLoaded = true
            print("✅ 模型載入成功")
        } catch {
            errorMessage = "模型載入失敗: \(error.localizedDescription)"
            throw error
        }
    }
    
    func unloadModel() {
        model = nil
        isModelLoaded = false
        print("🗑️ 模型已卸載")
    }
    
    // MARK: - File Analysis
    
    func analyzeFile(context: FileAnalysisContext) async throws -> AIAnalysis {
        guard isModelLoaded, let model = model else {
            throw LLMError.modelNotLoaded
        }
        
        // 1. 建立分析 prompt
        let prompt = buildPrompt(from: context)
        
        // 2. 執行推理
        let response = try await generateResponse(prompt: prompt, model: model)
        
        // 3. 解析回應
        let analysis = parseResponse(response, context: context)
        
        return analysis
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(from context: FileAnalysisContext) -> String {
        var prompt = """
        你是一個 macOS 檔案系統專家。請分析以下檔案/資料夾是否可以安全刪除：
        
        檔案名稱：\(context.fileName)
        類型：\(context.fileType)
        大小：\(context.formattedSize)
        路徑：\(context.sanitizedPath)
        """
        
        if let purpose = context.detectedPurpose {
            prompt += "\n偵測用途：\(purpose)"
        }
        
        if context.isDirectory, let fileCount = context.fileCount {
            prompt += "\n包含：\(fileCount) 個檔案"
        }
        
        if context.isSystemPath {
            prompt += "\n⚠️ 注意：這是系統路徑"
        }
        
        prompt += """
        
        
        請以 JSON 格式回答（不要包含任何其他文字）：
        {
          "safety_level": "safe/caution/danger",
          "explanation": "解釋這個檔案的用途（1-2句話）",
          "recommendation": "是否建議刪除及原因（1-2句話）",
          "recovery_hint": "若刪除後如何恢復（選填，1句話）"
        }
        """
        
        return prompt
    }
    
    private func generateResponse(prompt: String, model: LLMModel) async throws -> String {
        var fullResponse = ""
        
        // 使用 streaming API
        for try await token in model.generate(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: 0.3  // 較低溫度保持輸出穩定性
        ) {
            fullResponse += token
        }
        
        return fullResponse
    }
    
    private func parseResponse(_ response: String, context: FileAnalysisContext) -> AIAnalysis {
        // 嘗試解析 JSON 回應
        if let jsonData = response.data(using: .utf8),
           let json = try? JSONDecoder().decode(LLMResponse.self, from: jsonData) {
            
            let safetyLevel: AIAnalysis.SafetyLevel
            switch json.safety_level.lowercased() {
            case "safe": safetyLevel = .safe
            case "caution": safetyLevel = .caution
            case "danger": safetyLevel = .danger
            default: safetyLevel = .unknown
            }
            
            return AIAnalysis(
                fileName: context.fileName,
                filePath: context.sanitizedPath,
                safetyLevel: safetyLevel,
                explanation: json.explanation,
                recommendation: json.recommendation,
                recoveryHint: json.recovery_hint,
                timestamp: Date()
            )
        }
        
        // 解析失敗時的備援處理
        return AIAnalysis(
            fileName: context.fileName,
            filePath: context.sanitizedPath,
            safetyLevel: .unknown,
            explanation: "AI 分析回應格式錯誤",
            recommendation: "建議手動判斷是否刪除",
            recoveryHint: nil,
            timestamp: Date()
        )
    }
}

// MARK: - Supporting Types

private struct LLMResponse: Codable {
    let safety_level: String
    let explanation: String
    let recommendation: String
    let recovery_hint: String?
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case analysisTimeout
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "模型尚未載入"
        case .analysisTimeout:
            return "分析超時"
        }
    }
}
```

### Phase 3: UI 整合 (2-3 天)

#### 3.1 DetailPanel 修改

```swift
// Views/DetailPanel.swift (新增部分)
struct DetailPanel: View {
    let selectedNode: FileNode?
    @StateObject private var llmService = LLMService()
    @State private var showingAIAnalysis = false
    @State private var currentAnalysis: AIAnalysis?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailPanelHeader()
            
            if let node = selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 現有的詳細資訊...
                        
                        Divider()
                        
                        // AI 分析按鈕
                        AIAnalysisButton(
                            node: node,
                            llmService: llmService,
                            showingAnalysis: $showingAIAnalysis,
                            currentAnalysis: $currentAnalysis
                        )
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAIAnalysis) {
            if let analysis = currentAnalysis {
                AIAnalysisSheet(analysis: analysis)
            }
        }
        .task {
            // 應用程式啟動時預載入模型（背景執行）
            if !llmService.isModelLoaded {
                try? await llmService.loadModel()
            }
        }
    }
}
```

#### 3.2 AI 分析按鈕組件

```swift
struct AIAnalysisButton: View {
    let node: FileNode
    @ObservedObject var llmService: LLMService
    @Binding var showingAnalysis: Bool
    @Binding var currentAnalysis: AIAnalysis?
    @State private var isAnalyzing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 安全分析")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Button(action: { analyzeFile() }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text(isAnalyzing ? "分析中..." : "詢問 AI 是否可刪除")
                    if isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing || !llmService.isModelLoaded)
            
            if !llmService.isModelLoaded {
                Text("正在載入 AI 模型...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func analyzeFile() {
        isAnalyzing = true
        
        Task {
            do {
                let context = FileAnalysisContext(
                    fileName: node.name,
                    fileExtension: node.fileExtension,
                    fileType: node.fileType,
                    size: node.size,
                    formattedSize: node.formattedSize,
                    sanitizedPath: sanitizePath(node.url.path),
                    parentFolder: node.url.deletingLastPathComponent().lastPathComponent,
                    modificationDate: node.modificationDate,
                    isDirectory: node.isDirectory,
                    fileCount: node.isDirectory ? node.fileCount : nil,
                    directoryCount: node.isDirectory ? node.directoryCount : nil
                )
                
                currentAnalysis = try await llmService.analyzeFile(context: context)
                showingAnalysis = true
            } catch {
                print("❌ AI 分析失敗: \(error)")
            }
            
            isAnalyzing = false
        }
    }
    
    private func sanitizePath(_ path: String) -> String {
        return path.replacingOccurrences(
            of: #"/Users/[^/]+"#,
            with: "/Users/*",
            options: .regularExpression
        )
    }
}
```

#### 3.3 AI 分析結果視圖

```swift
// Views/AIAnalysisSheet.swift
struct AIAnalysisSheet: View {
    let analysis: AIAnalysis
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 安全等級徽章
                    SafetyLevelBadge(level: analysis.safetyLevel)
                    
                    // 檔案資訊
                    VStack(alignment: .leading, spacing: 8) {
                        Text("檔案")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(analysis.fileName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(analysis.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // AI 分析內容
                    AnalysisSection(title: "用途說明", content: analysis.explanation)
                    AnalysisSection(title: "刪除建議", content: analysis.recommendation)
                    
                    if let hint = analysis.recoveryHint {
                        AnalysisSection(title: "恢復方式", content: hint)
                    }
                    
                    // 免責聲明
                    DisclaimerView()
                }
                .padding()
            }
            .navigationTitle("AI 安全分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SafetyLevelBadge: View {
    let level: AIAnalysis.SafetyLevel
    
    var body: some View {
        HStack {
            Image(systemName: level.icon)
            Text(level.rawValue)
                .fontWeight(.semibold)
        }
        .font(.title2)
        .foregroundColor(level.color)
        .padding()
        .frame(maxWidth: .infinity)
        .background(level.color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct AnalysisSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(content)
                .font(.body)
        }
    }
}

struct DisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("免責聲明", systemImage: "info.circle")
                .font(.caption)
                .fontWeight(.semibold)
            
            Text("AI 建議僅供參考，無法保證 100% 準確。刪除重要檔案前請務必備份，或諮詢專業人士。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}
```

### Phase 4: 測試與優化 (3-4 天)

#### 4.1 功能測試案例

```
1. 系統檔案測試
   - /System/Library/...  → 應標記為 "危險"
   - /Applications/...    → 根據應用程式不同

2. 開發檔案測試
   - node_modules         → 應標記為 "安全"（可重新安裝）
   - .git                 → 應標記為 "謹慎"（版本控制）
   - build/               → 應標記為 "安全"（可重建）
   - DerivedData/         → 應標記為 "安全"（Xcode 快取）

3. 個人檔案測試
   - Documents/           → 應標記為 "謹慎"或"危險"
   - Downloads/temp.dmg   → 根據檔案年齡判斷
   
4. 快取和暫存檔案
   - ~/Library/Caches/    → 應標記為 "安全"
   - .DS_Store            → 應標記為 "安全"
```

#### 4.2 效能優化

```swift
// 優化項目：
1. 模型預載入：應用程式啟動時在背景載入
2. 結果快取：相同檔案不重複分析
3. 批次分析：支援一次分析多個檔案
4. 記憶體管理：分析完成後可選擇卸載模型
```

## 使用者體驗流程

```
1. 使用者選擇檔案/資料夾
   ↓
2. 在詳細資訊面板看到「詢問 AI 是否可刪除」按鈕
   ↓
3. 點擊按鈕（顯示分析中動畫）
   ↓
4. 3-5 秒後顯示分析結果 Sheet
   ↓
5. 查看安全等級、說明、建議
   ↓
6. (可選) 根據建議加入刪除列表
```

## 預期效能指標

- **模型載入時間**：5-10 秒（首次）
- **單檔分析時間**：2-5 秒
- **記憶體佔用**：+2-3 GB（模型載入時）
- **磁碟空間**：~2 GB（模型檔案）

## 潛在挑戰與解決方案

| 挑戰 | 解決方案 |
|------|---------|
| 模型下載大小 | 提供首次設置引導，背景下載 |
| 推理速度 | 使用 4-bit 量化，優化 prompt 長度 |
| 分析準確度 | Prompt 工程優化，加入更多 context |
| 記憶體壓力 | 支援按需載入/卸載模型 |
| 隱私顧慮 | 強調本地執行，提供路徑脫敏 |

## 後續擴展可能

1. **批次分析**：一次分析整個資料夾
2. **智慧推薦**：主動掃描並推薦可清理的檔案
3. **學習偏好**：記錄使用者決策，調整建議
4. **自訂規則**：允許使用者設定檔案類型規則
5. **多語言支援**：切換 prompt 語言

## 時程規劃

- **Week 1-2**: Phase 1-2 (環境設置 + Service 實作)
- **Week 3**: Phase 3 (UI 整合)
- **Week 4-5**: Phase 4 (測試與優化)
- **Total**: 約 4-5 週完成 MVP

---

此計劃提供了完整的實作路徑，從技術選型到具體程式碼，確保功能可行且使用者體驗良好。

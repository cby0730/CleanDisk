import Foundation
import MLX
import MLXLMCommon
import MLXLLM

/// 支援的 LLM 模型
enum LLMModel: String, CaseIterable, Identifiable {
    case qwen3SkyHighHermes4bit = "mlx-community/Qwen3-4B-Sky-High-Hermes-gabliterated-4bit"
    case qwen3Thinking25074bit = "mlx-community/Qwen3-4B-Thinking-2507-gabliterated-4bit"
    case qwen3SkyHighHermes8bit = "mlx-community/Qwen3-4B-Sky-High-Hermes-gabliterated-8bit"
    case qwen3Thinking25078bit = "mlx-community/Qwen3-4B-Thinking-2507-gabliterated-8bit"
    
    var id: String { rawValue }
    
    /// 顯示名稱
    var displayName: String {
        switch self {
        // Sky-High Hermes: 平衡速度與精度，包含快速 thinking（推薦）
        case .qwen3SkyHighHermes4bit: return "Qwen3 Sky-High Hermes 4bit (快速/推薦)"
        case .qwen3SkyHighHermes8bit: return "Qwen3 Sky-High Hermes 8bit (高精度/推薦)"
        // Thinking: 深度推理，最精準但最慢
        case .qwen3Thinking25074bit: return "Qwen3 Thinking 2507 4bit (最精準/較慢)"
        case .qwen3Thinking25078bit: return "Qwen3 Thinking 2507 8bit (最精準/最慢)"
        }
    }
    
    /// 預估大小
    var estimatedSize: String {
        switch self {
        case .qwen3SkyHighHermes4bit, .qwen3Thinking25074bit: return "~2.3 GB"
        case .qwen3SkyHighHermes8bit, .qwen3Thinking25078bit: return "~4.3 GB"
        }
    }
    
    /// 速度評級（1-5，5最快）
    var speedRating: Int {
        switch self {
        // Sky-High Hermes: 快速（推薦）
        case .qwen3SkyHighHermes4bit: return 5
        case .qwen3SkyHighHermes8bit: return 4
        // Thinking: 較慢但最精準
        case .qwen3Thinking25074bit: return 3
        case .qwen3Thinking25078bit: return 2
        }
    }
}

/// AI 刪除建議結果
struct FileDeletionSuggestion {
    let shouldDelete: Bool
    let confidence: Confidence
    let reasoning: String
    
    enum Confidence: String {
        case high = "高"
        case medium = "中"
        case low = "低"
    }
    
    var icon: String {
        shouldDelete ? "❌" : "✅"
    }
    
    var recommendation: String {
        shouldDelete ? "建議刪除" : "建議保留"
    }
}

/// LLM 服務，管理 MLX 模型的生命週期和 AI 建議生成
@MainActor
class LLMService: ObservableObject {
    // MARK: - Published State
    
    @Published var isModelLoaded: Bool = false
    @Published var isGenerating: Bool = false
    @Published var loadingProgress: String = ""
    @Published var error: AppError?
    @Published var selectedModel: LLMModel {
        didSet {
            // 當模型改變時，保存到 UserDefaults
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedLLMModel")
            // 如果有模型已載入，需要重新載入新模型
            if isModelLoaded {
                Task {
                    await reloadModel()
                }
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var model: ModelContainer?
    private var currentLoadedModel: LLMModel?
    
    // MARK: - Initialization
    
    init() {
        // 從 UserDefaults 載入上次的模型選擇
        if let savedModelId = UserDefaults.standard.string(forKey: "selectedLLMModel"),
           let savedModel = LLMModel(rawValue: savedModelId) {
            self.selectedModel = savedModel
        } else {
            // 預設使用 Qwen3 Sky-High Hermes 4bit（速度最快，推薦）
            self.selectedModel = .qwen3SkyHighHermes4bit
        }
    }
    
    // MARK: - Model Lifecycle
    
    /// 載入 MLX 模型
    func loadModel() async {
        guard !isModelLoaded else { return }
        
        isGenerating = true
        loadingProgress = "正在載入 \(selectedModel.displayName)..."
        error = nil
        
        do {
            let modelFactory = LLMModelFactory.shared
            let configuration = ModelConfiguration(id: selectedModel.rawValue)
            
            // 檢查模型是否已下載
            let modelPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/models/mlx-community")
                .appendingPathComponent(selectedModel.rawValue.components(separatedBy: "/").last ?? "")
            
            let wasDownloaded = FileManager.default.fileExists(atPath: modelPath.path)
            
            if wasDownloaded {
                loadingProgress = "載入模型中..."
            } else {
                loadingProgress = "下載模型中（\(selectedModel.estimatedSize)）..."
            }
            
            // 載入模型容器（如果需要會先下載）
            model = try await modelFactory.loadContainer(configuration: configuration)
            
            // 如果模型是剛下載的，顯示「載入模型中」狀態
            if !wasDownloaded {
                loadingProgress = "載入模型中..."
                // 給使用者至少 0.5 秒看到載入狀態
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            currentLoadedModel = selectedModel
            isModelLoaded = true
            loadingProgress = "模型已就緒"
            print("✅ LLM 模型載入成功: \(selectedModel.displayName)")
        } catch {
            self.error = AppError.llmError(.modelLoadFailed(error))
            loadingProgress = ""
            print("❌ LLM 模型載入失敗: \(error)")
        }
        
        isGenerating = false
    }
    
    /// 卸載模型以釋放記憶體
    func unloadModel() {
        model = nil
        currentLoadedModel = nil
        isModelLoaded = false
        loadingProgress = ""
        print("🗑️ LLM 模型已卸載")
    }
    
    /// 重新載入模型（切換模型時使用）
    private func reloadModel() async {
        print("🔄 切換模型: \(currentLoadedModel?.displayName ?? "無") → \(selectedModel.displayName)")
        unloadModel()
        await loadModel()
    }
    
    // MARK: - AI Suggestion
    
    /// 為指定檔案獲取 AI 刪除建議
    func getSuggestion(for fileNode: FileNode) async throws -> FileDeletionSuggestion {
        guard isModelLoaded, let model = model else {
            throw LLMError.modelNotLoaded
        }
        
        isGenerating = true
        loadingProgress = "AI 分析中..."
        
        // 確保至少顯示 1 秒的分析中狀態
        let startTime = Date()
        
        // 使用 do-catch 確保無論成功或失敗都能正確清理狀態
        do {
            // 建立 prompt
            let prompt = buildPrompt(for: fileNode)
            
            // 生成建議
            let response = try await generateResponse(prompt: prompt, model: model)
            
            // 解析回應
            let suggestion = parseSuggestion(from: response, fileNode: fileNode)
            
            // 確保至少顯示 1 秒的分析中狀態
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsedTime) * 1_000_000_000))
            }
            
            // 同步清理狀態（在 return 前）
            isGenerating = false
            loadingProgress = ""
            
            return suggestion
        } catch {
            // 錯誤時也要確保狀態被清理
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsedTime) * 1_000_000_000))
            }
            
            isGenerating = false
            loadingProgress = ""
            
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    /// 建立 AI prompt
    private func buildPrompt(for fileNode: FileNode) -> String {
        // Calculate time-based info
        let modDateStr = fileNode.modificationDate.map {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: $0, relativeTo: Date())
        } ?? "未知"
        
        let accessDateStr = fileNode.lastAccessDate.map {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: $0, relativeTo: Date())
        } ?? "未知"
        
        let daysSinceModStr = fileNode.daysSinceModified.map { "\($0) 天" } ?? "未知"
        
        return """
        # 角色定義
        你是一位 macOS 檔案系統安全專家，專門協助用戶判斷檔案是否可以安全刪除。你的首要原則是「安全優先」——當無法確定時，永遠建議保留。

        # 檔案資訊
        - 檔案名稱：\(fileNode.name)
        - 完整路徑：\(fileNode.url.path)
        - 檔案大小：\(fileNode.formattedSize)
        - 類型：\(fileNode.fileType)
        - 副檔名：\(fileNode.fileExtension.isEmpty ? "無" : ".\(fileNode.fileExtension)")
        - 最後修改：\(modDateStr)（\(daysSinceModStr)前）
        - 最後存取：\(accessDateStr)
        - 是否隱藏：\(fileNode.isHidden ? "是" : "否")
        - 是否鎖定：\(fileNode.isLocked ? "是" : "否")
        - 父資料夾：\(fileNode.parentFolderName)
        - 在快取目錄中：\(fileNode.isInCachesDir ? "是" : "否")
        - 在暫存目錄中：\(fileNode.isInTempDir ? "是" : "否")

        # 判斷規則（依優先順序）

        ## 絕對禁止刪除
        1. 路徑包含 `/System`、`/bin`、`/sbin`、`/usr`（除 `/usr/local`）
        2. 副檔名為 `.kext`、`.framework`、`.dylib`
        3. 檔案已被鎖定
        4. 路徑包含 `/Library/Extensions`
        5. 隱藏檔位於使用者家目錄根層級（如 `.zshrc`、`.bash_profile`）

        ## 建議刪除
        1. `.DS_Store` 檔案（Finder 會自動重建）
        2. `~/Library/Caches` 中超過 30 天未修改的檔案
        3. `~/Library/Logs` 中超過 7 天的 `.log` 檔案
        4. `~/Downloads` 中的 `.dmg`、`.pkg` 且已超過 30 天
        5. `.tmp`、`.temp`、`.cache` 副檔名的檔案

        ## 需謹慎判斷
        1. `~/Library/Application Support` 中的檔案只有在確認應用程式已被移除時才可刪除
        2. `.plist` 檔案依位置判斷：`~/Library/Preferences` 內通常可重建
        3. 7 天內修改過的檔案傾向保留

        # 思考步驟
        請依照以下步驟進行分析：
        1. 首先檢查路徑是否在禁止刪除清單中
        2. 檢查副檔名和檔案屬性
        3. 評估修改時間和使用頻率
        4. 考慮父資料夾的上下文
        5. 做出最終判斷

        # 輸出格式
        只輸出以下 JSON，不要包含任何其他文字、解釋或 markdown 標記：
        {
          "should_delete": true 或 false,
          "confidence": "high"、"medium" 或 "low",
          "reasoning": "繁體中文說明（50字內）"
        }

        # 範例

        輸入：路徑為 ~/Library/Caches/com.apple.Safari/Cache.db，30天前修改
        輸出：{"should_delete": true, "confidence": "high", "reasoning": "Safari 快取檔案，位於 Caches 目錄且超過 30 天未使用，可安全刪除"}

        輸入：路徑為 ~/.zshrc，隱藏檔
        輸出：{"should_delete": false, "confidence": "high", "reasoning": "重要的 shell 設定檔，刪除會影響終端機使用"}

        輸入：路徑為 /System/Library/Extensions/IOKit.kext
        輸出：{"should_delete": false, "confidence": "high", "reasoning": "系統核心擴充功能，刪除將導致系統無法啟動"}
        """
    }
    
    /// 生成 LLM 回應
    private func generateResponse(prompt: String, model: ModelContainer) async throws -> String {
        // 使用閉包內部的區域變數來累積回應，避免 Swift 6 並發警告
        let result: String = try await model.perform { context in
            var response = ""
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            
            let params = GenerateParameters(temperature: 0.3, topP: 0.9)
            let tokenStream = try generate(input: input, parameters: params, context: context)
            
            for await part in tokenStream {
                if let chunk = part.chunk {
                    response += chunk
                }
            }
            
            return response
        }
        
        return result
    }
    
    /// 解析 LLM 回應為結構化建議
    private func parseSuggestion(from response: String, fileNode: FileNode) -> FileDeletionSuggestion {
        // 嘗試解析 JSON
        if let jsonData = extractJSON(from: response),
           let parsed = try? JSONDecoder().decode(SuggestionResponse.self, from: jsonData) {
            
            let confidence: FileDeletionSuggestion.Confidence = {
                switch parsed.confidence.lowercased() {
                case "high", "高": return .high
                case "medium", "中": return .medium
                default: return .low
                }
            }()
            
            return FileDeletionSuggestion(
                shouldDelete: parsed.should_delete,
                confidence: confidence,
                reasoning: parsed.reasoning
            )
        }
        
        // Fallback: 使用啟發式規則
        return fallbackSuggestion(for: fileNode, response: response)
    }
    
    /// 從回應中提取 JSON
    private func extractJSON(from response: String) -> Data? {
        var cleanedResponse = response
        
        // 移除 <think>...</think> 標籤內容（Qwen3 Thinking 模型的思考過程）
        // 使用正則表達式移除所有 think 標籤及其內容
        if let thinkRange = cleanedResponse.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            cleanedResponse.removeSubrange(thinkRange)
        }
        
        // 也處理沒有閉合標籤的情況（只有 </think>）
        if let thinkEndIndex = cleanedResponse.range(of: "</think>") {
            cleanedResponse = String(cleanedResponse[thinkEndIndex.upperBound...])
        }
        
        // 尋找 JSON 物件
        guard let startIndex = cleanedResponse.firstIndex(of: "{"),
              let endIndex = cleanedResponse.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonString = String(cleanedResponse[startIndex...endIndex])
        return jsonString.data(using: .utf8)
    }
    
    /// 當 JSON 解析失敗時的 fallback 建議
    private func fallbackSuggestion(for fileNode: FileNode, response: String) -> FileDeletionSuggestion {
        print("⚠️ JSON 解析失敗，使用 fallback 邏輯")
        print("原始回應：\(response)")
        
        // 基於檔案類型的簡單啟發式
        let ext = fileNode.fileExtension.lowercased()
        let tempExtensions = ["tmp", "temp", "cache", "log", "bak", "old"]
        let shouldDelete = tempExtensions.contains(ext)
        
        let reasoning = shouldDelete
            ? "根據副檔名判斷，這可能是臨時檔案"
            : "無法確定，建議手動檢查後決定"
        
        return FileDeletionSuggestion(
            shouldDelete: shouldDelete,
            confidence: .low,
            reasoning: reasoning
        )
    }
}

// MARK: - Supporting Types

/// LLM 回應的 JSON 結構
private struct SuggestionResponse: Codable {
    let should_delete: Bool
    let confidence: String
    let reasoning: String
}


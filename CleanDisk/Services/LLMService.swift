import Foundation
import MLX
import MLXLMCommon
import MLXLLM

/// 支援的 LLM 模型
enum LLMModel: String, CaseIterable, Identifiable {
    case deepSeekR1 = "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-8bit"
    case llama32_3B = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    case qwen25_3B = "mlx-community/Qwen2.5-3B-Instruct-8bit"
    case qwen3_4B = "mlx-community/Qwen3-4B-4bit"
    case qwen3_4B_2507 = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    case llama3_8B = "mlx-community/Meta-Llama-3-8B-Instruct-4bit"
    case qwen3_8B = "mlx-community/Qwen3-8B-4bit"
    case gptOss20B = "mlx-community/gpt-oss-20b-MXFP4-Q8"
    
    var id: String { rawValue }
    
    /// 顯示名稱
    var displayName: String {
        switch self {
        case .deepSeekR1: return "DeepSeek R1 1.5B (最快)"
        case .llama32_3B: return "Llama 3.2 3B"
        case .qwen25_3B: return "Qwen 2.5 3B (推薦)"
        case .qwen3_4B: return "Qwen 3 4B"
        case .qwen3_4B_2507: return "Qwen 3 4B (2507)"
        case .llama3_8B: return "Llama 3 8B"
        case .qwen3_8B: return "Qwen 3 8B"
        case .gptOss20B: return "GPT-OSS 20B (最準確)"
        }
    }
    
    /// 預估大小
    var estimatedSize: String {
        switch self {
        case .deepSeekR1: return "~1.5 GB"
        case .llama32_3B: return "~2 GB"
        case .qwen25_3B: return "~3 GB"
        case .qwen3_4B, .qwen3_4B_2507: return "~2.5 GB"
        case .llama3_8B, .qwen3_8B: return "~5 GB"
        case .gptOss20B: return "~12 GB"
        }
    }
    
    /// 速度評級（1-5，5最快）
    var speedRating: Int {
        switch self {
        case .deepSeekR1: return 5
        case .llama32_3B, .qwen25_3B: return 4
        case .qwen3_4B, .qwen3_4B_2507: return 3
        case .llama3_8B, .qwen3_8B: return 2
        case .gptOss20B: return 1
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
    @Published var error: String?
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
            // 預設使用 Qwen 2.5 3B（平衡速度與準確度）
            self.selectedModel = .qwen25_3B
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
            self.error = "模型載入失敗: \(error.localizedDescription)"
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
        
        defer {
            Task {
                let elapsedTime = Date().timeIntervalSince(startTime)
                if elapsedTime < 1.0 {
                    try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsedTime) * 1_000_000_000))
                }
                await MainActor.run {
                    isGenerating = false
                    loadingProgress = ""
                }
            }
        }
        
        // 建立 prompt
        let prompt = buildPrompt(for: fileNode)
        
        // 生成建議
        let response = try await generateResponse(prompt: prompt, model: model)
        
        // 解析回應
        let suggestion = parseSuggestion(from: response, fileNode: fileNode)
        
        return suggestion
    }
    
    // MARK: - Private Helpers
    
    /// 建立 AI prompt
    private func buildPrompt(for fileNode: FileNode) -> String {
        let modDate = fileNode.modificationDate.map {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: $0, relativeTo: Date())
        } ?? "未知"
        
        return """
        你是一個檔案系統專家，幫助用戶判斷檔案是否應該刪除。
        
        檔案資訊：
        - 名稱：\(fileNode.name)
        - 路徑：\(fileNode.url.path)
        - 大小：\(fileNode.formattedSize)
        - 類型：\(fileNode.fileType)
        - 副檔名：\(fileNode.fileExtension.isEmpty ? "無" : fileNode.fileExtension)
        - 最後修改：\(modDate)
        - 是否隱藏檔：\(fileNode.isHidden ? "是" : "否")
        
        請根據以上資訊判斷這個檔案是否應該刪除。
        
        回應格式（JSON）：
        {
          "should_delete": true/false,
          "confidence": "high/medium/low",
          "reasoning": "簡短說明（繁體中文，50字內）"
        }
        
        只回傳 JSON，不要其他內容。
        """
    }
    
    /// 生成 LLM 回應
    private func generateResponse(prompt: String, model: ModelContainer) async throws -> String {
        var fullResponse = ""
        
        try await model.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            
            let params = GenerateParameters(temperature: 0.3, topP: 0.9)
            let tokenStream = try generate(input: input, parameters: params, context: context)
            
            for await part in tokenStream {
                if let chunk = part.chunk {
                    fullResponse += chunk
                }
            }
        }
        
        return fullResponse
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
        // 尋找 JSON 物件
        guard let startIndex = response.firstIndex(of: "{"),
              let endIndex = response.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonString = String(response[startIndex...endIndex])
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

/// LLM 服務錯誤
enum LLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI 模型尚未載入，請稍候"
        case .generationFailed(let message):
            return "AI 生成失敗：\(message)"
        }
    }
}

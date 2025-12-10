import Foundation

/// 應用程式統一錯誤類型
enum AppError: LocalizedError {
    /// 掃描相關錯誤
    case scanError(ScanError)
    
    /// 刪除相關錯誤
    case deletionError(DeletionError)
    
    /// LLM 相關錯誤
    case llmError(LLMError)
    
    /// 檔案系統錯誤
    case fileSystemError(FileSystemError)
    
    // MARK: - LocalizedError Protocol
    
    var errorDescription: String? {
        switch self {
        case .scanError(let error):
            return error.errorDescription
        case .deletionError(let error):
            return error.errorDescription
        case .llmError(let error):
            return error.errorDescription
        case .fileSystemError(let error):
            return error.errorDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .scanError(let error):
            return error.recoverySuggestion
        case .deletionError(let error):
            return error.recoverySuggestion
        case .llmError(let error):
            return error.recoverySuggestion
        case .fileSystemError(let error):
            return error.recoverySuggestion
        }
    }
    
    var failureReason: String? {
        switch self {
        case .scanError(let error):
            return error.failureReason
        case .deletionError(let error):
            return error.failureReason
        case .llmError(let error):
            return error.failureReason
        case .fileSystemError(let error):
            return error.failureReason
        }
    }
}

// MARK: - Scan Errors

/// 掃描相關錯誤
enum ScanError: LocalizedError, Equatable {
    case cancelled
    case pathNotFound(String)
    case permissionDenied(String)
    case invalidPath
    case unknown(Error)
    
    static func == (lhs: ScanError, rhs: ScanError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled):
            return true
        case (.pathNotFound(let p1), .pathNotFound(let p2)):
            return p1 == p2
        case (.permissionDenied(let p1), .permissionDenied(let p2)):
            return p1 == p2
        case (.invalidPath, .invalidPath):
            return true
        default:
            return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "掃描已取消"
        case .pathNotFound(let path):
            return "找不到路徑：\(path)"
        case .permissionDenied(let path):
            return "沒有權限存取：\(path)"
        case .invalidPath:
            return "路徑格式無效"
        case .unknown(let error):
            return "掃描失敗：\(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .cancelled:
            return "您可以重新開始掃描"
        case .pathNotFound:
            return "請檢查路徑是否正確，然後重試"
        case .permissionDenied:
            return "請檢查檔案權限設定，或嘗試使用其他路徑"
        case .invalidPath:
            return "請輸入有效的路徑"
        case .unknown:
            return "請重試，如果問題持續請檢查系統日誌"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .cancelled:
            return "使用者主動取消掃描"
        case .pathNotFound(let path):
            return "系統找不到指定的路徑：\(path)"
        case .permissionDenied(let path):
            return "程式沒有足夠的權限存取路徑：\(path)"
        case .invalidPath:
            return "提供的路徑不符合系統路徑格式"
        case .unknown(let error):
            return "發生未預期的錯誤：\(error)"
        }
    }
}

// MARK: - Deletion Errors

/// 刪除相關錯誤
enum DeletionError: LocalizedError {
    case fileNotFound(String)
    case permissionDenied(String)
    case trashFailed(String, Error)
    case emptyQueue
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "找不到檔案：\(path)"
        case .permissionDenied(let path):
            return "沒有權限刪除：\(path)"
        case .trashFailed(let path, _):
            return "無法移動到垃圾桶：\(path)"
        case .emptyQueue:
            return "刪除佇列是空的"
        case .unknown(let error):
            return "刪除失敗：\(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "檔案可能已被刪除，請重新整理檔案樹"
        case .permissionDenied:
            return "請檢查檔案權限，或使用管理員權限"
        case .trashFailed:
            return "請檢查垃圾桶是否已滿，或嘗試手動刪除"
        case .emptyQueue:
            return "請先將檔案加入刪除佇列"
        case .unknown:
            return "請重試，如果問題持續請檢查系統日誌"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .fileNotFound(let path):
            return "檔案不存在於路徑：\(path)"
        case .permissionDenied(let path):
            return "沒有足夠的權限刪除檔案：\(path)"
        case .trashFailed(let path, let error):
            return "將檔案移動到垃圾桶時失敗：\(path)，原因：\(error.localizedDescription)"
        case .emptyQueue:
            return "沒有檔案在刪除佇列中"
        case .unknown(let error):
            return "發生未預期的錯誤：\(error)"
        }
    }
}

// MARK: - LLM Errors

/// LLM 相關錯誤
enum LLMError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case generationFailed(Error)
    case invalidResponse
    case modelNotFound(String)
    case downloadFailed(Error)
    case outOfMemory
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "模型尚未載入"
        case .modelLoadFailed:
            return "模型載入失敗"
        case .generationFailed:
            return "AI 建議生成失敗"
        case .invalidResponse:
            return "AI 回應格式無效"
        case .modelNotFound(let modelName):
            return "找不到模型：\(modelName)"
        case .downloadFailed:
            return "模型下載失敗"
        case .outOfMemory:
            return "記憶體不足"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded:
            return "請先載入 AI 模型"
        case .modelLoadFailed(let error):
            let errorMsg = error.localizedDescription
            if errorMsg.contains("network") || errorMsg.contains("網路") {
                return "請檢查網路連線，然後重試"
            } else if errorMsg.contains("disk") || errorMsg.contains("磁碟") {
                return "請確保有足夠的磁碟空間"
            } else {
                return "請嘗試切換其他模型，或重新啟動應用程式"
            }
        case .generationFailed:
            return "請重試，如果問題持續可嘗試重新載入模型"
        case .invalidResponse:
            return "請重試，AI 模型可能需要重新載入"
        case .modelNotFound:
            return "請選擇其他可用的模型"
        case .downloadFailed:
            return "請檢查網路連線和磁碟空間，然後重試"
        case .outOfMemory:
            return "請關閉其他應用程式釋放記憶體，或選擇較小的模型"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .modelNotLoaded:
            return "模型尚未初始化或載入"
        case .modelLoadFailed(let error):
            return "模型載入過程中發生錯誤：\(error.localizedDescription)"
        case .generationFailed(let error):
            return "AI 建議生成時發生錯誤：\(error.localizedDescription)"
        case .invalidResponse:
            return "AI 回應的 JSON 格式無法解析"
        case .modelNotFound(let modelName):
            return "系統找不到模型檔案：\(modelName)"
        case .downloadFailed(let error):
            return "模型下載過程中發生錯誤：\(error.localizedDescription)"
        case .outOfMemory:
            return "系統記憶體不足以載入或執行模型"
        }
    }
}

// MARK: - File System Errors

/// 檔案系統錯誤
enum FileSystemError: LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case alreadyExists(String)
    case invalidOperation
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "無法存取：\(path)"
        case .notFound(let path):
            return "找不到：\(path)"
        case .alreadyExists(let path):
            return "已存在：\(path)"
        case .invalidOperation:
            return "無效的檔案操作"
        case .unknown(let error):
            return "檔案系統錯誤：\(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessDenied:
            return "請檢查檔案權限設定"
        case .notFound:
            return "請確認檔案或資料夾是否存在"
        case .alreadyExists:
            return "請選擇不同的名稱或位置"
        case .invalidOperation:
            return "此操作不適用於當前檔案類型"
        case .unknown:
            return "請重試，如果問題持續請檢查系統日誌"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .accessDenied(let path):
            return "程式沒有足夠的權限存取：\(path)"
        case .notFound(let path):
            return "檔案或資料夾不存在：\(path)"
        case .alreadyExists(let path):
            return "檔案或資料夾已存在：\(path)"
        case .invalidOperation:
            return "嘗試執行不支援的檔案操作"
        case .unknown(let error):
            return "發生未預期的檔案系統錯誤：\(error)"
        }
    }
}

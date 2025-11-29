# CleanDisk 開發者文件

本文件提供 CleanDisk 專案的詳細技術資訊，適合想要理解程式碼架構、參與開發或擴展功能的開發者。

## 📋 目錄

1. [專案架構](#專案架構)
2. [資料夾結構](#資料夾結構)
3. [核心組件](#核心組件)
4. [開發環境設置](#開發環境設置)
5. [建置和測試](#建置和測試)
6. [程式碼風格](#程式碼風格)
7. [貢獻指南](#貢獻指南)
8. [API 文檔](#api-文檔)
9. [設計決策](#設計決策)
10. [未來規劃](#未來規劃)

## 🏗️ 專案架構

CleanDisk 採用現代的 SwiftUI MVVM 架構，結合 Service Layer 模式，實現了良好的關注點分離。

### 架構層級

```
┌─────────────────────────────────────────┐
│                Views                    │ ← UI 層
│  ┌─────────────┐ ┌─────────────────────┐ │
│  │ SwiftUI     │ │ UI Components       │ │
│  │ Views       │ │ (Reusable)          │ │
│  └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│              ViewModels                 │ ← 狀態管理層
│  ┌─────────────┐ ┌─────────────────────┐ │
│  │ Observable  │ │ State Management    │ │
│  │ Objects     │ │ Business Logic      │ │
│  └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│               Services                  │ ← 業務邏輯層
│  ┌─────────────┐ ┌─────────────────────┐ │
│  │ File System │ │ File Deletion       │ │
│  │ Scanner     │ │ Service             │ │
│  └─────────────┘ └─────────────────────┘ │
│  ┌─────────────┐                         │
│  │ LLM Service │                         │
│  │ (MLX)       │                         │
│  └─────────────┘                         │
└─────────────────────────────────────────┘
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│                Models                   │ ← 資料模型層
│  ┌─────────────┐ ┌─────────────────────┐ │
│  │ FileNode    │ │ ScanProgress        │ │
│  │             │ │ Data Structures     │ │
│  └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────┘
```

### 設計原則

1. **單一職責原則**：每個類別和模組只負責一個特定功能
2. **開放封閉原則**：對擴展開放，對修改封閉
3. **依賴倒置原則**：高層模組不依賴低層模組
4. **組合優於繼承**：使用組合方式組織功能
5. **反應式設計**：使用 Combine 和 @Published 實現響應式 UI

## 📁 資料夾結構

```
CleanDisk/
├── CleanDisk/
│   ├── CleanDiskApp.swift           # 應用程式入口點
│   ├── ContentView.swift            # 主要內容視圖（簡化版）
│   ├── FileNode.swift               # 檔案節點資料模型
│   ├── FileSystemScanner.swift      # 檔案系統掃描服務
│   │
│   ├── Views/                       # UI 組件
│   │   ├── ContentView.swift        # 主要布局視圖
│   │   ├── SidebarControlPanel.swift # 側邊欄控制面板
│   │   ├── FileTreeView.swift       # 檔案樹顯示
│   │   ├── FileNodeRow.swift        # 檔案節點行組件
│   │   ├── FileIconHelper.swift     # 檔案圖示輔助工具
│   │   ├── DetailPanel.swift        # 詳細資訊面板
│   │   └── DeletionZone.swift       # 刪除功能 UI
│   │
│   ├── Services/                    # 業務邏輯服務
│   │   └── FileDeletionService.swift # 檔案刪除服務
│   │   └── LLMService.swift          # AI 智能分析服務 (基於 MLX)
│   │
│   ├── ViewModels/                  # 視圖模型
│   │   └── FileTreeManager.swift    # 檔案樹管理（已定義但未整合到 UI）
│   │
│   ├── Assets.xcassets/             # 應用程式資源
│   └── CleanDisk.entitlements       # 應用程式權限
│
├── CleanDisk.xcodeproj/             # Xcode 專案檔案
├── README.md                        # 使用者文件
├── DEVELOPER.md                     # 開發者文件
└── LICENSE                          # 授權檔案
```

## 🧩 核心組件

### 1. FileNode（資料模型）

```swift
class FileNode: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    @Published var size: Int64 = 0
    @Published var children: [FileNode] = []
    @Published var isExpanded: Bool = false
}
```

**職責**：
- 表示檔案系統中的一個節點（檔案或資料夾）
- 包含檔案的基本資訊和大小
- 支援樹狀結構（父子關係）
- 提供格式化顯示方法

**關鍵特性**：
- 使用 `@Published` 支援響應式 UI 更新
- 實現 `Identifiable` 支援 SwiftUI ForEach
- 提供拖放支援的 `itemProvider`

### 2. FileSystemScanner（掃描服務）

```swift
class FileSystemScanner: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var scanProgress: ScanProgress = ScanProgress()
    @Published var rootNode: FileNode?
    @Published var selectedNode: FileNode?
    @Published var errorMessage: String?
    @Published var deletionService = FileDeletionService()
}
```

**職責**：
- 掃描指定路徑的檔案系統
- 計算檔案和資料夾大小
- 建立檔案樹結構
- 管理掃描進度和狀態

**關鍵演算法**：
1. **兩階段掃描**：先計算總項目數，再進行實際掃描
2. **遞迴遍歷**：深度優先搜索檔案系統
3. **大小計算**：使用 `totalFileAllocatedSize` 取得真實磁碟佔用
4. **錯誤處理**：優雅處理權限拒絕和無法存取的檔案
5. **進度更新節流**：批次累積進度更新，每 0.1 秒更新一次 UI，減輕主執行緒負擔

### 3. FileDeletionService（刪除服務）

```swift
class FileDeletionService: ObservableObject {
    @Published var deletionQueue: [FileNode] = []
    @Published var isDeletingFiles: Bool = false
    @Published var deletionError: String?
    @Published var showDeletionConfirmation: Bool = false
}
```

**職責**：
- 管理待刪除檔案佇列
- 執行批次檔案刪除
- 處理刪除錯誤和回饋
- 與檔案系統互動（移動到垃圾桶）

**安全機制**：
- 使用 `FileManager.trashItem` 而非直接刪除
- 提供確認對話框
- 詳細的錯誤回報
- 詳細的錯誤回報
- 支援取消操作

### 4. LLMService (AI 服務)

```swift
class LLMService: ObservableObject {
    @Published var isModelLoaded: Bool = false
    @Published var isGenerating: Bool = false
    @Published var selectedModel: LLMModel
}
```

**職責**：
- 管理本地 LLM 模型的下載、載入與卸載
- 封裝 MLX 框架的複雜性
- 生成檔案刪除建議與理由

**技術細節**：
- 使用 `MLX` 與 `MLXLMCommon` 框架
- 支援多種量化模型 (4-bit/8-bit) 以適應不同硬體
- 實作了 Prompt Engineering 來引導模型輸出 JSON 格式
- 包含 JSON 解析失敗時的 Fallback 機制
- 智慧偵測模型下載狀態，提供準確的載入進度訊息
- 確保關鍵狀態至少顯示 0.5-1 秒，避免狀態切換過快

### 4. View 層組件

#### SidebarControlPanel
- 路徑選擇和輸入
- 掃描控制（開始/停止）
- 進度顯示
- 錯誤訊息展示

#### FileTreeView
- 檔案樹狀結構顯示
- 搜尋功能
- 展開/收合控制
- 工具列

#### FileNodeRow
- 單個檔案/資料夾的行顯示
- 大小視覺化（進度條和百分比）
- 檔案類型圖示
- 右鍵選單

#### DetailPanel
- 選中項目的詳細資訊
- 基本屬性顯示
- 目錄統計
- 最大檔案識別

#### DeletionZone
- 拖放目標區域
- 待刪除項目列表
- 批次操作控制
- 確認對話框

#### FileTreeManager（已定義但未整合）
- 定義了排序選項（名稱、大小、修改時間、類型）
- 提供隱藏檔案過濾邏輯
- 提供搜尋過濾方法
- **注意**：目前邏輯已實作但尚未整合到 UI 控制項中

## 💻 開發環境設置

### 必要工具

1. **Xcode 13.0+**
   - 支援 SwiftUI 和 macOS 11.0+ 開發
   - 包含 Swift 5.5+ 編譯器

2. **macOS 11.0+**
   - 開發和測試環境

3. **Git**
   - 版本控制工具

4. **Git LFS**
   - 用於下載大型模型文件（如果需要）

### 依賴庫 (Swift Package Manager)

- **MLX Swift**: Apple 的機器學習框架
- **MLX LLM**: 用於 LLM 推論的工具庫

### 環境配置

1. **克隆專案**
   ```bash
   git clone https://github.com/yourusername/CleanDisk.git
   cd CleanDisk
   ```

2. **開啟專案**
   ```bash
   open CleanDisk.xcodeproj
   ```

3. **配置簽名**
   - 在 Xcode 中選擇你的開發者團隊
   - 配置 Bundle Identifier

4. **設定權限**
   - 確認 `CleanDisk.entitlements` 中的權限設定
   - 必要時添加檔案系統存取權限

## 🔨 建置和測試

### 建置配置

```bash
# Debug 建置
xcodebuild -project CleanDisk.xcodeproj -scheme CleanDisk -configuration Debug

# Release 建置
xcodebuild -project CleanDisk.xcodeproj -scheme CleanDisk -configuration Release

# 匯出應用程式
xcodebuild -project CleanDisk.xcodeproj -scheme CleanDisk -configuration Release -archivePath CleanDisk.xcarchive archive
```

### 測試策略

1. **單元測試**
   - FileNode 功能測試
   - FileSystemScanner 邏輯測試
   - FileDeletionService 測試

2. **整合測試**
   - 檔案掃描完整流程
   - UI 與服務層互動

3. **手動測試**
   - 不同檔案系統結構
   - 大檔案和深層資料夾
   - 權限受限的路徑

### 效能測試

```swift
// 測試大型資料夾掃描效能
func testLargeDirectoryScan() {
    let scanner = FileSystemScanner()
    let expectation = XCTestExpectation(description: "Large directory scan")
    
    scanner.startScan(at: "/Applications")
    
    // 監控記憶體使用和執行時間
}
```

## 📝 程式碼風格

### Swift 程式碼規範

1. **命名規則**
   ```swift
   // 類別和結構體：PascalCase
   class FileSystemScanner { }
   struct FileNode { }
   
   // 變數和函式：camelCase
   var isScanning: Bool
   func startScan() { }
   
   // 常數：camelCase
   let maxFileSize = 1024 * 1024
   
   // 列舉：PascalCase
   enum ScanState {
       case idle, scanning, completed
   }
   ```

2. **SwiftUI 規範**
   ```swift
   // View 結構體命名
   struct ContentView: View { }
   struct FileNodeRow: View { }
   
   // State 變數
   @State private var isExpanded = false
   @StateObject private var scanner = FileSystemScanner()
   
   // 環境變數
   @EnvironmentObject var scanner: FileSystemScanner
   ```

3. **註解規範**
   ```swift
   /// 檔案系統掃描器，負責掃描指定路徑並建立檔案樹
   class FileSystemScanner: ObservableObject {
       
       /// 開始掃描指定路徑
       /// - Parameter path: 要掃描的路徑
       func startScan(at path: String) {
           // 實作...
       }
   }
   ```

### 專案特定規範

1. **檔案組織**
   - 每個 View 一個檔案
   - 相關的小組件可以放在同一個檔案
   - Service 類別獨立檔案

2. **依賴管理**
   - 優先使用組合而非繼承
   - 通過 @EnvironmentObject 傳遞依賴
   - 避免循環依賴

3. **錯誤處理**
   ```swift
   do {
       let result = try riskyOperation()
       // 處理成功情況
   } catch {
       // 記錄錯誤並更新 UI
       print("❌ 操作失敗: \(error.localizedDescription)")
       errorMessage = "操作失敗: \(error.localizedDescription)"
   }
   ```

## 🤝 貢獻指南

### 開發流程

1. **建立分支**
   ```bash
   git checkout -b feature/new-feature
   git checkout -b bugfix/fix-issue
   git checkout -b improvement/enhance-performance
   ```

2. **開發和測試**
   - 遵循程式碼風格指南
   - 添加必要的註解
   - 確保所有測試通過

3. **提交變更**
   ```bash
   git add .
   git commit -m "feat: 添加新功能描述"
   git push origin feature/new-feature
   ```

4. **建立 Pull Request**
   - 提供清楚的變更描述
   - 包含相關的 Issue 連結
   - 添加螢幕截圖（如果是 UI 變更）

### Commit 訊息規範

```
type(scope): description

[optional body]

[optional footer]
```

**類型**：
- `feat`: 新功能
- `fix`: 錯誤修復
- `docs`: 文件更新
- `style`: 程式碼格式調整
- `refactor`: 程式碼重構
- `test`: 測試相關
- `chore`: 其他變更

**範例**：
```
feat(scanner): 添加網路磁碟掃描支援

- 支援 SMB 和 AFP 協定
- 添加網路連線狀態檢查
- 改善錯誤處理機制

Closes #123
```

### 程式碼審查檢查清單

- [ ] 程式碼符合專案風格指南
- [ ] 添加了適當的註解和文件
- [ ] 新功能包含對應的測試
- [ ] 沒有明顯的效能問題
- [ ] UI 變更在不同螢幕尺寸下正常運作
- [ ] 處理了潛在的錯誤情況
- [ ] 沒有硬編碼的值或路徑

## 📚 API 文檔

### FileSystemScanner

#### 屬性

```swift
@Published var isScanning: Bool
// 是否正在進行掃描

@Published var scanProgress: ScanProgress
// 掃描進度資訊

@Published var rootNode: FileNode?
// 掃描結果的根節點

@Published var selectedNode: FileNode?
// 目前選中的檔案節點

@Published var errorMessage: String?
// 錯誤訊息（如果有）
```

#### 方法

```swift
func startScan(at path: String)
// 開始掃描指定路徑

func updateFileTreeAfterDeletion(deletedNodes: [FileNode])
// 刪除檔案後更新檔案樹
```

### FileDeletionService

#### 屬性

```swift
@Published var deletionQueue: [FileNode]
// 待刪除檔案佇列

@Published var isDeletingFiles: Bool
// 是否正在刪除檔案

@Published var deletionError: String?
// 刪除錯誤訊息

var deletionQueueTotalSize: Int64
// 待刪除檔案總大小
```

#### 方法

```swift
func addToDeletionQueue(_ node: FileNode)
// 添加檔案到刪除佇列

func removeFromDeletionQueue(_ node: FileNode)
// 從刪除佇列移除檔案

func clearDeletionQueue()
// 清空刪除佇列

func executeFileDeletion(completion: @escaping ([String]) -> Void)
// 執行批次刪除

### LLMService

#### 屬性

```swift
@Published var isModelLoaded: Bool
// 模型是否已載入記憶體

@Published var isGenerating: Bool
// 是否正在生成建議

@Published var selectedModel: LLMModel
// 當前選擇使用的模型
```

#### 方法

```swift
func loadModel() async
// 下載並載入選定的模型

func getSuggestion(for fileNode: FileNode) async throws -> FileDeletionSuggestion
// 分析檔案並回傳刪除建議
```
```

### FileNode

#### 屬性

```swift
let id: UUID
// 唯一識別碼

let url: URL
// 檔案系統路徑

let name: String
// 檔案或資料夾名稱

let isDirectory: Bool
// 是否為資料夾

@Published var size: Int64
// 檔案或資料夾大小

@Published var children: [FileNode]
// 子項目（如果是資料夾）

var formattedSize: String
// 格式化的大小字串

var fileType: String
// 檔案類型描述

var modificationDate: Date?
// 最後修改時間
```

## 🧠 設計決策

### 為什麼選擇 SwiftUI？

1. **原生效能**：直接使用 Apple 的原生框架
2. **響應式設計**：天然支援狀態驅動的 UI 更新
3. **現代語法**：聲明式語法更簡潔易讀
4. **未來導向**：Apple 主推的 UI 框架

### 為什麼拆分 ContentView？

**問題**：原始的 ContentView.swift 有 825 行，包含多個不同的 UI 組件，違反了單一職責原則。

**解決方案**：
- 將每個主要 UI 區塊拆分成獨立的 View
- 創建可重用的小組件
- 使用組合模式組建複雜的 UI

**好處**：
- 更好的程式碼可讀性
- 更容易維護和修改
- 支援單獨測試每個組件
- 更好的團隊協作

### 為什麼分離刪除服務？

**問題**：原始的 FileSystemScanner 同時負責掃描和刪除，職責不清楚。

**解決方案**：
- 創建獨立的 FileDeletionService
- 通過組合而非繼承的方式整合

**好處**：
- 單一職責原則
- 更容易測試
- 可以獨立重用刪除功能
- 更清楚的程式碼結構

### 為什麼使用兩階段掃描？

**問題**：無法準確顯示掃描進度。

**解決方案**：
1. **第一階段**：快速遍歷檔案系統計算總項目數
2. **第二階段**：詳細掃描並計算大小

**權衡**：
- 增加了一些額外的時間開銷
- 但提供了更好的使用者體驗
- 用戶可以看到準確的進度百分比

### 為什麼使用 totalFileAllocatedSize？

**問題**：不同的大小計算方法會得到不同的結果。

**選擇順序**：
1. `totalFileAllocatedSize` - 包含稀疏檔案的實際佔用
2. `fileAllocatedSize` - 檔案分配大小
3. `fileSize` - 檔案邏輯大小

**原因**：更準確反映磁碟空間使用情況。

### 為什麼使用進度更新節流？

**問題**：掃描大量檔案時，過於頻繁的 UI 更新會造成主執行緒負擔和視覺卡頓。

**解決方案**：
- 在背景執行緒累積進度更新（處理的項目數和當前路徑）
- 每 0.1 秒批次更新一次 UI
- 掃描結束時強制更新最後一次進度

**好處**：
- 大幅減少主執行緒的更新頻率
- 提升 UI 響應性和流暢度
- 避免過度頻繁的畫面重繪
- 更好的整體掃描效能

### 為什麼要偵測模型下載狀態？

**問題**：模型載入有兩種情況（首次下載 vs 本地載入），用戶需要知道當前正在進行哪個步驟。

**解決方案**：
- 檢查模型檔案是否存在於本地快取
- 根據狀態顯示不同的進度訊息：
  - 本地存在：只顯示「載入模型中...」
  - 不存在：顯示「下載模型中（大小）...」→「載入模型中...」
- 確保關鍵狀態至少顯示 0.5-1 秒

**好處**：
- 用戶清楚知道當前進度
- 避免狀態訊息切換過快導致看不清楚
- 提供更好的視覺回饋和等待體驗
- 首次下載時可以預估所需時間

## 🔮 未來規劃

### 短期目標（下個版本）

1. **效能優化**
   - [x] 實作取消掃描功能
   - [x] 添加記憶體使用優化（掃描結果清除功能）
   - [ ] 優化大型檔案系統的掃描速度

2. **使用者體驗改善**
   - [ ] 整合排序 UI 控制項（邏輯已實作於 FileTreeManager）
   - [ ] 整合隱藏檔案切換 UI（邏輯已實作於 FileTreeManager）
   - [ ] 添加鍵盤快捷鍵支援
   - [ ] 改善搜尋功能（正規表達式支援）
   - [ ] 添加檔案類型過濾 UI

3. **錯誤處理**
   - [ ] 更詳細的錯誤訊息
   - [ ] 權限問題的處理指引
   - [ ] 網路磁碟的支援

### 中期目標

1. **進階功能**
   - [ ] 重複檔案檢測
   - [ ] 檔案內容分析
   - [ ] 匯出報告功能
   - [ ] 磁碟使用趨勢分析

2. **整合功能**
   - [ ] Spotlight 整合
   - [ ] Quick Look 預覽支援
   - [ ] 自動化腳本支援

3. **國際化**
   - [ ] 多語言支援
   - [ ] 在地化日期和數字格式

### 長期目標

1. **雲端功能**
   - [ ] iCloud 支援
   - [ ] 設定同步
   - [ ] 備份建議

2. **智慧功能**
   - [x] 機器學習驅動的清理建議 (已實作 LLMService)
   - [ ] 自動分類檔案
   - [ ] 預測性磁碟清理

3. **擴展性**
   - [ ] 插件系統
   - [ ] API 支援
   - [ ] 命令列工具

### 技術債務清理

1. **程式碼品質**
   - [ ] 增加單元測試覆蓋率到 80%
   - [ ] 實作整合測試
   - [ ] 效能基準測試

2. **架構改善**
   - [ ] 實作正式的 ViewModel 層
   - [ ] 添加依賴注入容器
   - [ ] 改善錯誤處理架構

3. **文件更新**
   - [ ] API 文件自動生成
   - [ ] 使用者手冊
   - [ ] 貢獻者指南

## 🆘 疑難排解

### 常見開發問題

1. **建置失敗**
   ```
   解決方案：
   - 檢查 Xcode 版本（需要 13.0+）
   - 清理 build 資料夾 (⌘+Shift+K)
   - 重新啟動 Xcode
   ```

2. **權限問題**
   ```
   解決方案：
   - 檢查 entitlements 檔案
   - 確認應用程式簽名正確
   - 在系統偏好設定中授予檔案存取權限
   ```

3. **記憶體使用過高**
   ```
   解決方案：
   - 使用 autoreleasepool 包裝遞迴操作
   - 實作分頁載入大型資料夾
   - 優化 FileNode 的記憶體佔用
   ```

### 效能調優

1. **掃描速度優化**
   ```swift
   // 使用並行處理（謹慎使用）
   DispatchQueue.concurrentPerform(iterations: contents.count) { index in
       // 處理檔案
   }
   ```

2. **UI 響應性**
   ```swift
   // 確保 UI 更新在主執行緒
   DispatchQueue.main.async {
       self.scanProgress.processedItems += 1
   }
   ```

## 📞 聯繫開發團隊

- **技術問題**：在 GitHub Issues 中建立技術問題
- **功能請求**：使用 Feature Request 模板
- **安全問題**：私下聯繫維護者
- **一般討論**：使用 GitHub Discussions

---

**最後更新**：2025年11月30日
**文件版本**：1.0.1
**對應程式碼版本**：v1.0.1

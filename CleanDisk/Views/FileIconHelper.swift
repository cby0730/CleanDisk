import SwiftUI

/// 檔案圖示和顏色輔助工具
struct FileIconHelper {
    
    /// 取得檔案圖示
    static func getIcon(for node: FileNode) -> String {
        if node.isDirectory {
            return node.isExpanded ? "folder.fill" : "folder"
        }
        
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "txt", "md", "rtf":
            return "doc.text"
        case "pdf":
            return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "video"
        case "mp3", "m4a", "wav", "flac":
            return "music.note"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        case "app":
            return "app"
        case "dmg":
            return "opticaldisc"
        default:
            return "doc"
        }
    }
    
    /// 取得檔案圖示顏色
    static func getColor(for node: FileNode) -> Color {
        if node.isDirectory {
            return .blue
        }
        
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return .green
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "m4a", "wav", "flac":
            return .orange
        case "app":
            return .blue
        default:
            return .primary
        }
    }
}

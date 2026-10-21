import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
    static func chooseDirectory(message: String = "选择生成项目的目标位置") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseTemplateToImport() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "导入"
        panel.message = "选择导出的模板 JSON 文件"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseTemplateDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        panel.prompt = "导出"
        panel.message = "模板会保存为 JSON，可发给同事导入"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

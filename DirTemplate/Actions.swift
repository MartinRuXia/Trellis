import AppKit

@MainActor
enum Actions {
    static func importTemplate(_ store: TemplateStore) {
        guard let url = FilePanels.chooseTemplateToImport() else { return }
        do {
            try store.importTemplate(from: url)
        } catch {
            store.present(error)
        }
    }

    static func exportSelectedTemplate(_ store: TemplateStore) {
        guard let template = store.selectedTemplate else { return }
        guard let url = FilePanels.chooseTemplateDestination(defaultName: "\(template.name).json") else { return }
        do {
            try store.exportTemplate(template.id, to: url)
            store.flash("已导出模板")
        } catch {
            store.present(error)
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

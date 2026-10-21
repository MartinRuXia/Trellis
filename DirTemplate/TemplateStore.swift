import Foundation
import AppKit
import Combine

// MARK: - 弹窗描述

struct AppDialog: Identifiable {
    enum Kind {
        case newTemplate
        case renameTemplate(UUID)
        case deleteTemplate(UUID)
        case renameProject(UUID)
        case conflict(String)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let confirmTitle: String
    let hasTextField: Bool
    let destructive: Bool
}

// MARK: - 模板库

@MainActor
final class TemplateStore: ObservableObject {

    @Published private(set) var templates: [Template] = []
    @Published private(set) var recents: [GeneratedProject] = []

    @Published var selectedTemplateID: UUID? {
        didSet {
            guard oldValue != selectedTemplateID else { return }
            selectedNodeID = nil
            editingNodeID = nil
            editingMode = .none
            editingText = ""
            canvasActive = false
            expandAll(in: selectedTemplate)
        }
    }

    @Published var selectedNodeID: UUID?
    @Published var editingNodeID: UUID?
    @Published var editingMode: FolderEditMode = .none

    /// 画布是否处于激活状态：只有激活时，回车 / Tab 才作用于思维导图
    @Published var canvasActive = false
    /// 结构版本号：新增 / 删除 / 移动时递增，供画布做布局动画
    @Published private(set) var treeRevision = 0
    /// 行内输入框的实时文本（不发布，避免每次按键触发全局刷新）
    var editingText = ""
    @Published var expandedNodes: Set<UUID> = []

    @Published var draftProjectName: String = ""
    @Published var draftTarget: String = "" {
        didSet {
            guard oldValue != draftTarget else { return }
            UserDefaults.standard.set(draftTarget, forKey: Keys.lastTarget)
        }
    }

    @Published var revealAfterCreate: Bool = {
        if UserDefaults.standard.object(forKey: Keys.reveal) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.reveal)
    }() {
        didSet { UserDefaults.standard.set(revealAfterCreate, forKey: Keys.reveal) }
    }

    @Published var lastCreated: GeneratedProject?
    @Published var focusNamePulse = 0

    @Published var dialog: AppDialog?
    @Published var dialogText: String = ""

    @Published var errorMessage: String?
    @Published var toast: String?

    private enum Keys {
        static let lastTarget = "lastTargetPath"
        static let reveal = "revealAfterCreate"
    }

    private struct Library: Codable, Sendable {
        var templates: [Template]
        var recents: [GeneratedProject]
    }

    private let fileManager = FileManager.default
    private let libraryURL: URL
    private let saveQueue = DispatchQueue(label: "com.martin.trellis.library", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    // MARK: 初始化

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let legacyFolder = support.appendingPathComponent("DirTemplate", isDirectory: true)
        var folder = support.appendingPathComponent("Trellis", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path),
           fileManager.fileExists(atPath: legacyFolder.path) {
            try? fileManager.copyItem(at: legacyFolder, to: folder)
        }
        #if DEBUG
        var override = ProcessInfo.processInfo.environment["DIRTEMPLATE_STORE_DIR"]
        if let index = CommandLine.arguments.firstIndex(of: "--store"),
           index + 1 < CommandLine.arguments.count {
            override = CommandLine.arguments[index + 1]
        }
        if let override, !override.isEmpty {
            folder = URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        libraryURL = folder.appendingPathComponent("library.json")

        load()
        draftTarget = UserDefaults.standard.string(forKey: Keys.lastTarget) ?? ""
        selectedTemplateID = templates.first?.id
        expandAll(in: selectedTemplate)

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveNow()
            }
        }
    }

    // MARK: 计算属性

    var selectedTemplate: Template? {
        guard let id = selectedTemplateID else { return nil }
        return templates.first { $0.id == id }
    }

    var draftTargetURL: URL? {
        draftTarget.isEmpty ? nil : URL(fileURLWithPath: draftTarget, isDirectory: true)
    }

    var trimmedProjectName: String {
        draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nameValidationError: String? {
        DirectoryBuilder.validateName(trimmedProjectName)
    }

    var currentIssues: [DirectoryBuilder.Issue] {
        guard let template = selectedTemplate else { return [] }
        let context = NameContext(projectName: trimmedProjectName.isEmpty ? "项目" : trimmedProjectName,
                                  date: Date())
        return DirectoryBuilder.issues(nodes: template.nodes, context: context)
    }

    var previewPath: String {
        guard let target = draftTargetURL else { return "请先选择目标位置" }
        let name = trimmedProjectName.isEmpty ? "{项目名称}" : trimmedProjectName
        return target.appendingPathComponent(name, isDirectory: true).path
    }

    // MARK: 模板增删改

    func beginNewTemplate() {
        dialogText = uniqueTemplateName(base: "新模板")
        dialog = AppDialog(
            kind: .newTemplate,
            title: "新建模板",
            message: "模板只保存目录结构，不会创建任何文件。创建后可继续添加文件夹。",
            confirmTitle: "创建",
            hasTextField: true,
            destructive: false
        )
    }

    func beginRenameTemplate(_ template: Template) {
        dialogText = template.name
        dialog = AppDialog(
            kind: .renameTemplate(template.id),
            title: "重命名模板",
            message: "只修改模板名称，不影响已生成的项目文件夹。",
            confirmTitle: "保存",
            hasTextField: true,
            destructive: false
        )
    }

    func requestDeleteTemplate(_ template: Template) {
        dialog = AppDialog(
            kind: .deleteTemplate(template.id),
            title: "删除模板「\(template.name)」？",
            message: "只会删除模板，不会动磁盘上已经生成的项目文件夹。此操作无法撤销。",
            confirmTitle: "删除",
            hasTextField: false,
            destructive: true
        )
    }

    func createTemplate(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let template = Template(name: name, nodes: [])
        templates.append(template)
        selectedTemplateID = template.id
        save()
        flash("已创建模板「\(name)」")
    }

    func duplicateTemplate(_ id: UUID) {
        guard let source = templates.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueTemplateName(base: source.name + " 副本")
        copy.nodes = source.nodes.map { $0.cloned() }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        templates.append(copy)
        selectedTemplateID = copy.id
        save()
        flash("已复制为「\(copy.name)」")
    }

    func updateTemplateInfo(_ id: UUID, name rawName: String, note: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard templates[index].name != name || (templates[index].note ?? "") != trimmedNote else { return }
        templates[index].name = name
        templates[index].note = trimmedNote.isEmpty ? nil : trimmedNote
        templates[index].updatedAt = Date()
        save()
    }

    func renameTemplate(_ id: UUID, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].name = name
        templates[index].updatedAt = Date()
        save()
    }

    func deleteTemplate(_ id: UUID) {
        templates.removeAll { $0.id == id }
        if selectedTemplateID == id {
            selectedTemplateID = templates.first?.id
        }
        save()
        flash("模板已删除")
    }

    func loadSample() {
        let sample = Template(name: "示例：视频项目", nodes: [
            FolderNode(name: "01 素材", children: [
                FolderNode(name: "视频"),
                FolderNode(name: "音频"),
                FolderNode(name: "图片")
            ]),
            FolderNode(name: "02 工程", children: [
                FolderNode(name: "剪辑"),
                FolderNode(name: "调色"),
                FolderNode(name: "声音")
            ]),
            FolderNode(name: "03 输出", children: [
                FolderNode(name: "成片"),
                FolderNode(name: "预览")
            ]),
            FolderNode(name: "04 交付", children: [
                FolderNode(name: "{日期} 交付")
            ])
        ])
        templates.append(sample)
        selectedTemplateID = sample.id
        save()
        flash("已载入示例模板")
    }

    // MARK: 文件夹增删改

    func activateCanvas() {
        if !canvasActive { canvasActive = true }
    }

    /// 点击画布时把键盘焦点从顶部输入框收回来，否则 Tab 会被系统当成焦点切换
    func focusCanvas() {
        canvasActive = true
        let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        window?.makeFirstResponder(nil)
    }

    private func bumpTree() {
        treeRevision += 1
    }

    func deactivateCanvas() {
        canvasActive = false
        endEditingFromOutside()
    }

    /// 点击画布外时，把正在编辑的名字落定；空名字会直接移除占位节点
    func endEditingFromOutside() {
        guard let id = editingNodeID else { return }
        commitEdit(id, text: editingText, command: .end)
    }

    func beginAddNode(parent: UUID?) {
        guard selectedTemplateID != nil else { return }
        if let id = addNode(parent: parent, name: "") {
            selectedNodeID = id
            editingNodeID = id
            editingMode = .creating
            editingText = ""
            canvasActive = true
        }
    }

    /// 在指定节点后面插入同级文件夹，并进入编辑（回车连续新建的入口）
    func beginSibling(after id: UUID?) {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }

        guard let anchorID = id ?? selectedNodeID,
              templates[index].nodes.node(with: anchorID) != nil else {
            beginAddNode(parent: nil)
            return
        }

        let node = FolderNode(name: "")
        guard templates[index].nodes.insertAfter(anchorID, node: node) else { return }
        if let parentID = templates[index].nodes.parentID(of: anchorID) {
            expandedNodes.insert(parentID)
        }
        templates[index].updatedAt = Date()
        selectedNodeID = node.id
        editingNodeID = node.id
        editingMode = .creating
        editingText = ""
        canvasActive = true
        bumpTree()
        save()
    }

    /// 在指定节点下创建子文件夹，并进入编辑（Tab 的入口）
    func beginChild(of id: UUID?) {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }

        let node = FolderNode(name: "")
        if let parentID = id, templates[index].nodes.node(with: parentID) != nil {
            guard templates[index].nodes.mutateNode(parentID, { $0.children.append(node) }) else { return }
            expandedNodes.insert(parentID)
        } else {
            templates[index].nodes.append(node)
        }
        templates[index].updatedAt = Date()
        selectedNodeID = node.id
        editingNodeID = node.id
        editingMode = .creating
        editingText = ""
        canvasActive = true
        bumpTree()
        save()
    }

    @discardableResult
    func addNode(parent: UUID?, name: String = "") -> UUID? {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return nil }
        let node = FolderNode(name: name)
        if let parent {
            guard templates[index].nodes.mutateNode(parent, { $0.children.append(node) }) else { return nil }
            expandedNodes.insert(parent)
        } else {
            templates[index].nodes.append(node)
        }
        templates[index].updatedAt = Date()
        selectedNodeID = node.id
        bumpTree()
        save()
        return node.id
    }

    func beginRename(_ id: UUID) {
        selectedNodeID = id
        editingNodeID = id
        editingMode = .renaming
        editingText = selectedTemplate?.nodes.node(with: id)?.name ?? ""
        canvasActive = true
    }

    /// 提交行内编辑：
    /// - 回车：新建模式下立刻建下一个同级；重命名模式下只保存
    /// - Tab：保存并建一个子级
    /// - 失焦：只保存
    /// - 空名称：取消并移除占位节点
    func commitEdit(_ id: UUID, text: String, command: FolderEditCommand) {
        guard editingNodeID == id else { return }
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }

        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = editingMode

        guard !name.isEmpty else {
            cancelEdit(id)
            return
        }

        guard templates[index].nodes.mutateNode(id, { $0.name = name }) else { return }
        templates[index].updatedAt = Date()
        editingNodeID = nil
        editingMode = .none
        editingText = ""
        save()

        switch command {
        case .sibling:
            if mode == .creating {
                beginSibling(after: id)
            }
        case .child:
            beginChild(of: id)
        case .end:
            break
        }
    }

    func cancelEdit(_ id: UUID) {
        guard editingNodeID == id else { return }
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }

        if editingMode == .creating {
            _ = templates[index].nodes.removeNode(id)
            templates[index].updatedAt = Date()
            if selectedNodeID == id { selectedNodeID = nil }
            save()
        }
        editingNodeID = nil
        editingMode = .none
        editingText = ""
    }

    func deleteNode(_ id: UUID) {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }
        guard templates[index].nodes.removeNode(id) else { return }
        templates[index].updatedAt = Date()
        if selectedNodeID == id { selectedNodeID = nil }
        editingNodeID = nil
        editingMode = .none
        editingText = ""
        bumpTree()
        save()
    }

    func duplicateNode(_ id: UUID) {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }),
              let node = templates[index].nodes.node(with: id) else { return }

        var copy = node.cloned()
        let siblings: [FolderNode]
        if let parentID = templates[index].nodes.parentID(of: id),
           let parent = templates[index].nodes.node(with: parentID) {
            siblings = parent.children
        } else {
            siblings = templates[index].nodes
        }
        copy.name = uniqueSiblingName(base: node.name, among: siblings.map(\.name))

        guard templates[index].nodes.insertAfter(id, node: copy) else { return }
        templates[index].updatedAt = Date()
        selectedNodeID = copy.id
        bumpTree()
        save()
    }

    func moveNode(_ id: UUID, offset: Int) {
        guard let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }) else { return }
        guard templates[index].nodes.moveNode(id, offset: offset) else { return }
        templates[index].updatedAt = Date()
        bumpTree()
        save()
    }

    func canMove(_ id: UUID, offset: Int) -> Bool {
        guard let template = selectedTemplate else { return false }
        return template.nodes.canMoveNode(id, offset: offset)
    }

    func toggleExpanded(_ id: UUID) {
        if expandedNodes.contains(id) {
            expandedNodes.remove(id)
        } else {
            expandedNodes.insert(id)
        }
    }

    // MARK: 生成项目

    func generateNow() {
        guard let template = selectedTemplate else { return }

        if let error = nameValidationError {
            focusNamePulse += 1
            present(StoreError(error))
            return
        }
        guard let target = draftTargetURL else {
            present(StoreError("请先选择目标位置"))
            return
        }
        let context = NameContext(projectName: trimmedProjectName, date: Date())
        if let issue = DirectoryBuilder.issues(nodes: template.nodes, context: context).first {
            present(StoreError("模板中有文件夹名称不正确：\(issue.message)（\(issue.path)）"))
            return
        }

        let root = target.appendingPathComponent(trimmedProjectName, isDirectory: true)
        if fileManager.fileExists(atPath: root.path) {
            let suggestion = DirectoryBuilder.uniqueName(trimmedProjectName, in: target)
            dialog = AppDialog(
                kind: .conflict(suggestion),
                title: "已存在同名文件夹",
                message: "目标位置已存在「\(trimmedProjectName)」。\n可以改用「\(suggestion)」，或返回修改项目名称。",
                confirmTitle: "使用「\(suggestion)」",
                hasTextField: false,
                destructive: false
            )
            return
        }

        performGenerate(name: trimmedProjectName)
    }

    private func performGenerate(name: String) {
        guard let template = selectedTemplate, let target = draftTargetURL else { return }
        do {
            let project = try generate(template: template, name: name, in: target)
            lastCreated = project
            draftProjectName = ""
            flash("已生成「\(project.name)」")
            if revealAfterCreate {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
            }
        } catch {
            present(error)
        }
    }

    private func generate(template: Template, name: String, in target: URL) throws -> GeneratedProject {
        let context = NameContext(projectName: name, date: Date())
        let root = target.appendingPathComponent(name, isDirectory: true)
        do {
            try DirectoryBuilder.create(nodes: template.nodes, at: root, context: context)
        } catch let failure as BuildFailure {
            throw failure
        } catch {
            throw BuildFailure(path: root.path, underlying: error)
        }

        let project = GeneratedProject(name: name,
                                       templateName: template.name,
                                       path: root.path,
                                       createdAt: Date())
        recents.insert(project, at: 0)
        if recents.count > 50 { recents = Array(recents.prefix(50)) }
        save()
        return project
    }

    // MARK: 最近创建

    func beginRenameProject(_ project: GeneratedProject) {
        dialogText = project.name
        dialog = AppDialog(
            kind: .renameProject(project.id),
            title: "重命名项目文件夹",
            message: "会同时重命名磁盘上的文件夹：\(project.path)",
            confirmTitle: "重命名",
            hasTextField: true,
            destructive: false
        )
    }

    func renameProject(id: UUID, to raw: String) {
        guard let index = recents.firstIndex(where: { $0.id == id }) else { return }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = DirectoryBuilder.validateName(name) {
            present(StoreError(error))
            return
        }
        let oldURL = URL(fileURLWithPath: recents[index].path, isDirectory: true)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else { return }
        guard fileManager.fileExists(atPath: oldURL.path) else {
            present(StoreError("文件夹不存在，可能已被移动或删除"))
            return
        }
        guard !fileManager.fileExists(atPath: newURL.path) else {
            present(StoreError("同级目录已存在「\(name)」"))
            return
        }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            recents[index].name = name
            recents[index].path = newURL.path
            if lastCreated?.id == id { lastCreated = recents[index] }
            save()
            flash("已重命名为「\(name)」")
        } catch {
            present(BuildFailure(path: oldURL.path, underlying: error))
        }
    }

    func removeRecent(_ project: GeneratedProject) {
        recents.removeAll { $0.id == project.id }
        if lastCreated?.id == project.id { lastCreated = nil }
        save()
    }

    // MARK: 导入导出

    func importTemplate(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var template = try decoder.decode(Template.self, from: data)
        template.id = UUID()
        template.name = uniqueTemplateName(base: template.name)
        template.nodes = template.nodes.map { $0.cloned() }
        template.createdAt = Date()
        template.updatedAt = Date()
        templates.append(template)
        selectedTemplateID = template.id
        save()
        flash("已导入「\(template.name)」")
    }

    func exportTemplate(_ id: UUID, to url: URL) throws {
        guard let template = templates.first(where: { $0.id == id }) else {
            throw StoreError("模板不存在")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(template).write(to: url, options: .atomic)
    }

    // MARK: 弹窗提交

    func commitDialog() {
        guard let current = dialog else { return }
        let text = dialogText.trimmingCharacters(in: .whitespacesAndNewlines)
        dialog = nil

        switch current.kind {
        case .newTemplate:
            guard !text.isEmpty else { return }
            createTemplate(named: text)
        case .renameTemplate(let id):
            guard !text.isEmpty else { return }
            renameTemplate(id, to: text)
        case .deleteTemplate(let id):
            deleteTemplate(id)
        case .renameProject(let id):
            guard !text.isEmpty else { return }
            renameProject(id: id, to: text)
        case .conflict(let suggestion):
            performGenerate(name: suggestion)
        }
    }

    // MARK: 提示

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func flash(_ message: String) {
        toast = message
        let current = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if toast == current { toast = nil }
        }
    }

    // MARK: 持久化

    private func expandAll(in template: Template?) {
        guard let template else {
            expandedNodes = []
            return
        }
        expandedNodes = Set(template.nodes.allIDs())
    }

    private func uniqueTemplateName(base: String) -> String {
        var candidate = base
        var index = 2
        while templates.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(index)"
            index += 1
        }
        return candidate
    }

    private func uniqueSiblingName(base: String, among names: [String]) -> String {
        var candidate = base + " 副本"
        var index = 2
        while names.contains(candidate) {
            candidate = "\(base) 副本 \(index)"
            index += 1
        }
        return candidate
    }

    private func save() {
        pendingSave?.cancel()
        let library = Library(templates: templates, recents: recents)
        let url = libraryURL
        let item = DispatchWorkItem {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(library)
                try data.write(to: url, options: .atomic)
            } catch {
                print("保存模板库失败：\(error)")
            }
        }
        pendingSave = item
        saveQueue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    func saveNow() {
        pendingSave?.cancel()
        do {
            let library = Library(templates: templates, recents: recents)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(library)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("保存模板库失败：\(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let library = try? decoder.decode(Library.self, from: data) {
            templates = library.templates
            recents = library.recents
        } else {
            print("模板库文件无法解析：\(libraryURL.path)")
        }
    }
}

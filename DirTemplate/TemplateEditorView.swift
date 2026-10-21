import SwiftUI
import AppKit

struct TemplateEditorView: View {
    @EnvironmentObject private var store: TemplateStore

    @State private var nameDraft = ""
    @State private var noteDraft = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var noteFocused: Bool

    var body: some View {
        if let template = store.selectedTemplate {
            VStack(spacing: 0) {
                header(template)
                Divider()
                if store.editingMode == .creating {
                    creatingBanner
                }
                MindMapView(template: template)
                Divider()
                footer
            }
            .background(Theme.canvas)
            .onAppear { syncDrafts(template) }
            .onChange(of: template.id) { _, _ in syncDrafts(template) }
        } else {
            EmptyView()
        }
    }

    // MARK: 头部

    private func header(_ template: Template) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text("编辑模板")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 8)

                Spacer(minLength: 8)

                Button {
                    store.beginAddNode(parent: nil)
                } label: {
                    Label("添加根文件夹", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("重命名模板…") { store.beginRenameTemplate(template) }
                    Button("复制模板") { store.duplicateTemplate(template.id) }
                    Button("导出模板…") { Actions.exportSelectedTemplate(store) }
                    Divider()
                    Button("删除模板", role: .destructive) { store.requestDeleteTemplate(template) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多模板操作")
            }

            HStack(spacing: 8) {
                Text("模板名称")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("模板名称", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 210)
                    .focused($nameFocused)
                    .onSubmit { commitInfo(template) }

                Text("备注")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                TextField("可选", text: $noteDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 340)
                    .focused($noteFocused)
                    .onSubmit { commitInfo(template) }
            }

            Text("\(template.folderCount) 个文件夹 · \(template.maxDepth) 级 · 更新于 \(template.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onTapGesture {
            store.deactivateCanvas()
        }
        .onChange(of: nameFocused) { _, focused in
            if focused { store.deactivateCanvas() } else { commitInfo(template) }
        }
        .onChange(of: noteFocused) { _, focused in
            if focused { store.deactivateCanvas() } else { commitInfo(template) }
        }
        .onChange(of: template.name) { _, newValue in
            if !nameFocused { nameDraft = newValue }
        }
        .onChange(of: template.note) { _, newValue in
            if !noteFocused { noteDraft = newValue ?? "" }
        }
    }

    private func syncDrafts(_ template: Template) {
        nameDraft = template.name
        noteDraft = template.note ?? ""
    }

    private func commitInfo(_ template: Template) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = template.name
            return
        }
        store.updateTemplateInfo(template.id, name: trimmed, note: noteDraft)
        nameDraft = trimmed
    }

    // MARK: 新建提示条

    private var creatingBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
            Text("输入名称后：回车 继续建同级 · Tab 建子级 · Esc 取消")
                .font(.system(size: 10))
            Spacer(minLength: 0)
            Button("取消命名") {
                if let id = store.editingNodeID { store.cancelEdit(id) }
            }
            .buttonStyle(.link)
            .font(.system(size: 10))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Theme.accent.opacity(0.07))
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.beginAddNode(parent: nil)
            } label: {
                Label("添加根文件夹", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("单击选中 · 再点改名 · 回车 同级 · Tab 子级 · 滚轮平移")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

// MARK: - 原生行内输入框（回车 / Tab / Esc 由 NSTextField 代理接管）

struct InlineNameField: NSViewRepresentable {
    let nodeID: UUID
    let text: String
    let onTextChange: (String) -> Void
    let onCommit: (String, FolderEditCommand) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 12)
        field.controlSize = .small
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.identifier = NSUserInterfaceItemIdentifier("inline-folder-field")
        context.coordinator.field = field
        context.coordinator.nodeID = nodeID
        scheduleFocus(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.nodeID != nodeID else { return }

        context.coordinator.nodeID = nodeID
        context.coordinator.finished = false
        field.stringValue = text
        field.currentEditor()?.string = text
        scheduleFocus(field)
    }

    private func scheduleFocus(_ field: NSTextField) {
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            if window.firstResponder !== field.currentEditor() {
                window.makeFirstResponder(field)
            }
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineNameField
        var nodeID: UUID
        weak var field: NSTextField?
        var finished = false

        init(_ parent: InlineNameField) {
            self.parent = parent
            self.nodeID = parent.nodeID
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                finish(.sibling, text: textView.string)
                return true
            case #selector(NSResponder.insertTab(_:)):
                finish(.child, text: textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard !finished else { return true }
                finished = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field else { return }
            parent.onTextChange(field.stringValue)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            finish(.end)
        }

        private func finish(_ command: FolderEditCommand, text: String? = nil) {
            guard !finished, let field else { return }
            finished = true
            parent.onCommit(text ?? field.stringValue, command)
        }
    }
}

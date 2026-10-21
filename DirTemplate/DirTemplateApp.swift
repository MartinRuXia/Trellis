import SwiftUI
import AppKit

@main
struct DirTemplateApp: App {
    @StateObject private var store = TemplateStore()

    var body: some Scene {
        WindowGroup("目录模板") {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            // 文件
            CommandGroup(replacing: .newItem) {
                Button("新建模板") { store.beginNewTemplate() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("导入模板…") { Actions.importTemplate(store) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("导出当前模板…") { Actions.exportSelectedTemplate(store) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store.selectedTemplate == nil)
            }

            // 编辑菜单：保证输入框的复制 / 粘贴 / 剪切 / 全选走系统标准 responder
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("重做") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("剪切") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("拷贝") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("粘贴") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Button("全选") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }

            // 项目
            CommandMenu("项目") {
                Button("生成项目") { store.generateNow() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(store.selectedTemplate == nil)

                Divider()

                Button("新建文件夹") {
                    store.beginAddNode(parent: store.selectedNodeID)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store.selectedTemplate == nil)

                Button("重命名文件夹") {
                    if let id = store.selectedNodeID { store.beginRename(id) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.selectedNodeID == nil)

                Button("删除文件夹") {
                    if let id = store.selectedNodeID { store.deleteNode(id) }
                }
                .disabled(store.selectedNodeID == nil)

                Divider()

                Button("在 Finder 中显示最近生成的项目") {
                    if let project = store.lastCreated {
                        Actions.reveal(project.url)
                    }
                }
                .disabled(store.lastCreated == nil)
            }
        }
    }
}

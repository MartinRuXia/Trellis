import AppKit

/// 当焦点在树里（选中了某个文件夹、且没有在输入框里）时，
/// 接管回车 / Tab：回车建同级，Tab 建子级。
@MainActor
final class TreeKeyMonitor {
    private var token: Any?
    private weak var store: TemplateStore?

    func install(store: TemplateStore) {
        self.store = store
        guard token == nil else { return }

        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let store = self.store else { return event }
                return self.handle(event, store: store)
            }
        }
    }

    func uninstall() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }

    private func handle(_ event: NSEvent, store: TemplateStore) -> NSEvent? {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              window.attachedSheet == nil else { return event }

        // 只有思维导图画布处于激活状态时，Tab / 回车才归画布处理
        guard store.canvasActive else { return event }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else { return event }
        // 正在行内编辑：回车 = 保存并建同级，Tab = 保存并建子级
        if let editingID = store.editingNodeID {
            guard let editor = window.firstResponder as? NSTextView,
                  !editor.hasMarkedText() else { return event }
            switch event.keyCode {
            case 36, 76:
                store.commitEdit(editingID, text: editor.string, command: .sibling)
                return nil
            case 48:
                store.commitEdit(editingID, text: editor.string, command: .child)
                return nil
            default:
                return event
            }
        }

        guard let selected = store.selectedNodeID else { return event }

        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSControl {
            return event
        }

        switch event.keyCode {
        case 36, 76: // Return / 小键盘 Enter
            store.beginSibling(after: selected)
            return nil
        case 48: // Tab
            store.beginChild(of: selected)
            return nil
        default:
            return event
        }
    }
}

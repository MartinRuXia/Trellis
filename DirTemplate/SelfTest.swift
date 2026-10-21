#if DEBUG
import AppKit

/// 仅在 Debug 构建、且设置了 DIRTEMPLATE_SELFTEST=1 时运行。
/// 用于在没有屏幕录制权限的环境里验证菜单、生成流程，并导出窗口截图。
@MainActor
enum SelfTest {
    private static var started = false

    static var isRequested: Bool {
        CommandLine.arguments.contains("--selftest")
            || ProcessInfo.processInfo.environment["DIRTEMPLATE_SELFTEST"] == "1"
    }

    static func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var storeDirectory: String? {
        argument("--store") ?? ProcessInfo.processInfo.environment["DIRTEMPLATE_STORE_DIR"]
    }

    static var screenshotPath: String? {
        argument("--shot") ?? ProcessInfo.processInfo.environment["DIRTEMPLATE_SHOT"]
    }

    static func run(store: TemplateStore) {
        guard !started else { return }
        started = true

        if let shot = SelfTest.screenshotPath {
            freopen(shot + ".log", "w", stdout)
        }
        setvbuf(stdout, nil, _IONBF, 0)
        print("[SelfTest] 开始")
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            print("[SelfTest] 超时，强制退出")
            exit(2)
        }

        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("  ✓ \(name)")
            } else {
                failures += 1
                print("  ✗ \(name)")
            }
        }

        print("[SelfTest] 菜单")
        let titles = NSApp.mainMenu?.items.map(\.title) ?? []
        print("  菜单栏：\(titles.joined(separator: " | "))")
        check(titles.contains("编辑"), "存在「编辑」菜单")
        if let edit = NSApp.mainMenu?.items.first(where: { $0.title == "编辑" })?.submenu {
            let items = edit.items.map(\.title)
            print("  编辑菜单：\(items.joined(separator: " | "))")
            let paste = edit.items.first { $0.title == "粘贴" }
            check(paste != nil, "编辑菜单含「粘贴」")
            check(paste?.keyEquivalent == "v", "粘贴快捷键为 V")
            check(paste?.keyEquivalentModifierMask.contains(.command) == true, "粘贴带 ⌘")
            let copy = edit.items.first { $0.title == "拷贝" }
            check(copy?.keyEquivalent == "c", "拷贝快捷键为 ⌘C")
        } else {
            check(false, "编辑菜单可展开")
        }

        print("[SelfTest] 连续建文件夹（回车 / Tab）")
        store.createTemplate(named: "交互测试")
        store.beginAddNode(parent: nil)
        guard let firstID = store.editingNodeID else {
            print("  ✗ 回车没有进入编辑")
            finish(failures: failures + 1)
            return
        }
        check(store.selectedTemplate?.folderCount == 1, "先创建一个占位文件夹")

        // 输入父级名称后按 Tab：保存并建子级
        store.commitEdit(firstID, text: "01 素材", command: .child)
        check(store.selectedTemplate?.folderCount == 2, "Tab：保存并自动建子级（实际 \(store.selectedTemplate?.folderCount ?? -1)）")
        check(store.editingNodeID != nil, "焦点落在新建的子级上")

        // 子级名称后按回车：保存并建同级
        guard let secondID = store.editingNodeID else {
            finish(failures: failures + 1)
            return
        }
        store.commitEdit(secondID, text: "视频", command: .sibling)
        check(store.selectedTemplate?.folderCount == 3, "回车：保存并自动建同级（实际 \(store.selectedTemplate?.folderCount ?? -1)）")
        if let template = store.selectedTemplate {
            let first = template.nodes.first
            check(first?.name == "01 素材", "第一个文件夹名称正确")
            check(first?.children.count == 2, "两个子级都挂在「01 素材」下面")
            check(first?.children.first?.name == "视频", "子级名称正确")
        }

        // 空名称回车：取消并移除占位节点
        if let thirdID = store.editingNodeID {
            store.commitEdit(thirdID, text: "", command: .end)
        }
        check(store.selectedTemplate?.folderCount == 2, "空名称取消后不留下空文件夹")

        // 重命名模式：回车只保存，不再新建
        if let template = store.selectedTemplate, let rootID = template.nodes.first?.id {
            store.beginRename(rootID)
            store.commitEdit(rootID, text: "01 素材改名", command: .sibling)
            check(store.selectedTemplate?.folderCount == 2, "重命名模式回车只保存，不新建同级")
            check(store.selectedTemplate?.nodes.first?.name == "01 素材改名", "重命名生效")
        }
        if let testID = store.selectedTemplate?.id {
            store.deleteTemplate(testID)
        }

        print("[SelfTest] 生成流程")
        store.createTemplate(named: "自检模板")
        guard let template = store.selectedTemplate else {
            print("  ✗ 创建模板失败")
            finish(failures: failures + 1)
            return
        }
        check(template.name == "自检模板", "模板已创建")

        guard let material = store.addNode(parent: nil, name: "01 素材") else {
            print("  ✗ 添加根目录失败")
            finish(failures: failures + 1)
            return
        }
        store.addNode(parent: material, name: "视频")
        store.addNode(parent: material, name: "音频")
        if let project = store.addNode(parent: nil, name: "02 工程") {
            store.addNode(parent: project, name: "剪辑")
            store.addNode(parent: project, name: "调色")
        }
        store.addNode(parent: nil, name: "03 交付")
        store.addNode(parent: nil, name: "{日期} 交付说明")
        check(store.selectedTemplate?.folderCount == 8, "模板共 8 个文件夹")

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrellisSelfTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        store.draftProjectName = "自检项目"
        store.draftTarget = target.path
        store.revealAfterCreate = false
        store.generateNow()

        let root = target.appendingPathComponent("自检项目", isDirectory: true)
        let fm = FileManager.default
        check(fm.fileExists(atPath: root.appendingPathComponent("01 素材/视频").path), "嵌套文件夹已创建")
        check(fm.fileExists(atPath: root.path), "根文件夹已创建")
        check(store.recents.first?.path == root.path, "写入最近创建")

        // 重命名生成的项目文件夹
        if let project = store.recents.first {
            store.renameProject(id: project.id, to: "自检项目 改名")
            let renamed = target.appendingPathComponent("自检项目 改名", isDirectory: true)
            check(fm.fileExists(atPath: renamed.path), "项目文件夹重命名生效")
            check(store.recents.first?.name == "自检项目 改名", "记录同步更新")
        }

        print("[SelfTest] 真实输入框按键")
        Task { @MainActor in
            // 确保窗口在前台，避免无激活启动时输入框拿不到焦点
            if let window = NSApp.windows.first {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
            }
            try? await Task.sleep(for: .milliseconds(500))

            let windows = NSApp.windows
            print("WINDOWS count=\(windows.count) active=\(NSApp.isActive) key=\(NSApp.keyWindow != nil)")
            for window in windows {
                print("WIN \(type(of: window)) visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame)")
            }

            store.createTemplate(named: "按键测试")
            store.beginAddNode(parent: nil)
            try? await Task.sleep(for: .milliseconds(500))
            let fieldResult = await inlineFieldCheck(store: store)
            print(fieldResult.message)
            var extraFailure = fieldResult.ok ? 0 : 1

            // 未命名节点：点击外部应自动清理
            store.createTemplate(named: "边界测试")
            store.beginAddNode(parent: nil)
            let beforeCount = store.selectedTemplate?.folderCount ?? -1
            store.endEditingFromOutside()
            let afterCount = store.selectedTemplate?.folderCount ?? -1
            if beforeCount == 1 && afterCount == 0 {
                print("  ✓ 空名字点击外部后自动移除占位节点")
            } else {
                extraFailure += 1
                print("  ✗ 空名字没有清理（\(beforeCount) → \(afterCount)）")
            }

            // Tab 作用域：画布未激活时不应建子级
            store.beginAddNode(parent: nil)
            if let id = store.editingNodeID {
                store.commitEdit(id, text: "父级", command: .end)
            }
            if let parentID = store.selectedTemplate?.nodes.first?.id,
               let window = NSApp.windows.first(where: { $0.isVisible }) {
                store.selectedNodeID = parentID
                store.deactivateCanvas()
                window.makeFirstResponder(nil)
                let baseCount = store.selectedTemplate?.folderCount ?? -1
                sendKey(window: window, keyCode: 48, characters: "\t")
                try? await Task.sleep(for: .milliseconds(200))
                let inactiveCount = store.selectedTemplate?.folderCount ?? -1
                if inactiveCount == baseCount {
                    print("  ✓ 画布未激活时 Tab 不会建子级")
                } else {
                    extraFailure += 1
                    print("  ✗ 画布未激活时 Tab 仍然生效")
                }

                store.activateCanvas()
                window.makeFirstResponder(nil)
                sendKey(window: window, keyCode: 48, characters: "\t")
                try? await Task.sleep(for: .milliseconds(300))
                let activeCount = store.selectedTemplate?.folderCount ?? -1
                if activeCount == baseCount + 1 {
                    print("  ✓ 激活画布后 Tab 正常建子级")
                } else {
                    extraFailure += 1
                    print("  ✗ 激活画布后 Tab 未生效（\(baseCount) → \(activeCount)）")
                }
            }
            if let boundaryID = store.selectedTemplate?.id {
                store.deleteTemplate(boundaryID)
            }

            // 焦点交还：从顶部输入框点回画布后，Tab 要能建子级
            store.createTemplate(named: "焦点测试")
            store.beginAddNode(parent: nil)
            if let id = store.editingNodeID {
                store.commitEdit(id, text: "父级", command: .end)
            }
            if let window = NSApp.windows.first(where: { $0.isVisible }),
               let content = window.contentView,
               let field = firstEditableField(in: content) {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
                window.makeFirstResponder(field)
                try? await Task.sleep(for: .milliseconds(150))
                let fieldHadFocus = window.firstResponder is NSTextView
                store.focusCanvas()
                try? await Task.sleep(for: .milliseconds(150))
                let resigned = !(window.firstResponder is NSTextView)
                if fieldHadFocus && resigned {
                    print("  ✓ 点击画布后输入框交还键盘焦点")
                } else {
                    extraFailure += 1
                    print("  ✗ 焦点没有交还（field=\(fieldHadFocus), resigned=\(resigned)）")
                }

                if let parentID = store.selectedTemplate?.nodes.first?.id {
                    store.selectedNodeID = parentID
                    store.activateCanvas()
                    store.focusCanvas()
                    let before = store.selectedTemplate?.folderCount ?? -1
                    sendKey(window: window, keyCode: 48, characters: "\t")
                    try? await Task.sleep(for: .milliseconds(300))
                    let after = store.selectedTemplate?.folderCount ?? -1
                    if after == before + 1 {
                        print("  ✓ 交还焦点后 Tab 正常建子级")
                    } else {
                        extraFailure += 1
                        print("  ✗ 交还焦点后 Tab 仍未建子级（\(before) → \(after)）")
                    }
                }
            } else {
                extraFailure += 1
                print("  ✗ 找不到可测试的输入框")
            }
            if let focusTestID = store.selectedTemplate?.id {
                store.deleteTemplate(focusTestID)
            }

            // 性能：连续创建节点
            store.createTemplate(named: "性能测试")
            let start = CFAbsoluteTimeGetCurrent()
            for index in 0..<60 {
                store.beginAddNode(parent: nil)
                if let id = store.editingNodeID {
                    store.commitEdit(id, text: "节点\(index)", command: .end)
                }
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "  · 连续创建 60 个节点：%.1f ms", elapsed))
            if elapsed < 500 {
                print("  ✓ 节点创建性能正常")
            } else {
                extraFailure += 1
                print("  ✗ 节点创建偏慢")
            }
            if let perfID = store.selectedTemplate?.id {
                store.deleteTemplate(perfID)
            }

            if let buttonTest = store.templates.first(where: { $0.name == "按键测试" }) {
                store.deleteTemplate(buttonTest.id)
            }

            // 截图前切回有内容的模板
            if let review = store.templates.first(where: { $0.name == "自检模板" }) {
                store.selectedTemplateID = review.id
            }
            store.draftProjectName = "秋日宣传片"
            store.toast = nil
            store.activateCanvas()
            if let first = store.selectedTemplate?.nodes.first?.children.first?.id {
                store.selectedNodeID = first
            }

            try? await Task.sleep(for: .seconds(2))
            if let path = SelfTest.screenshotPath {
                snapshot(to: path)
            }
            try? FileManager.default.removeItem(at: target)
            store.deleteTemplate(template.id)
            finish(failures: failures + extraFailure)
        }
    }

    private static func firstEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField,
           field.isEditable,
           field.identifier?.rawValue != "inline-folder-field" {
            return field
        }
        for sub in view.subviews {
            if let found = firstEditableField(in: sub) { return found }
        }
        return nil
    }

    @MainActor
    private static func inlineFieldCheck(store: TemplateStore) async -> (ok: Bool, message: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let editor = window.firstResponder as? NSTextView,
              editor.delegate is NSTextField else {
            return (false, "  ✗ 找不到正在编辑的输入框")
        }

        editor.string = "键盘父级"
        sendKey(window: window, keyCode: 36, characters: "\r")
        try? await Task.sleep(for: .milliseconds(320))

        guard store.selectedTemplate?.folderCount == 2, store.editingNodeID != nil else {
            return (false, "  ✗ 真实输入框回车没有创建同级（folderCount=\(store.selectedTemplate?.folderCount ?? -1)）")
        }

        guard let window2 = NSApp.windows.first(where: { $0.isVisible }),
              let editor2 = window2.firstResponder as? NSTextView else {
            return (false, "  ✗ 新输入框没有获得焦点")
        }

        editor2.string = "键盘子级"
        sendKey(window: window2, keyCode: 48, characters: "\t")
        try? await Task.sleep(for: .milliseconds(320))

        let roots = store.selectedTemplate?.nodes ?? []
        let child = roots.count == 2 ? roots[1].children.first : nil
        let ok = store.selectedTemplate?.folderCount == 3
            && roots.count == 2
            && roots[1].children.count == 1
            && store.editingNodeID == child?.id
        return (ok, ok ? "  ✓ 真实输入框：回车建同级、Tab 建子级（正在命名子级）" : "  ✗ 真实输入框 Tab 没有建子级")
    }

    private static func sendKey(window: NSWindow, keyCode: UInt16, characters: String) {
        guard let event = NSEvent.keyEvent(with: .keyDown,
                                           location: .zero,
                                           modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber,
                                           context: nil,
                                           characters: characters,
                                           charactersIgnoringModifiers: characters,
                                           isARepeat: false,
                                           keyCode: keyCode) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else {
            print("  ✗ 无法获取窗口")
            return
        }
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.center()
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let view = content.superview ?? content
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("  ✗ 无法渲染窗口")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("  截图已写入 \(path)")
        }
    }

    private static func finish(failures: Int) {
        print("[SelfTest] 结束，失败 \(failures) 项")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
#endif

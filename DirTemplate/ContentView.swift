import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TemplateStore
    @State private var keyMonitor = TreeKeyMonitor()

    private var dialogBinding: Binding<Bool> {
        Binding(get: { store.dialog != nil },
                set: { if !$0 { store.dialog = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 244)
                .frame(maxHeight: .infinity)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alert(LocalizedStringKey("操作没有完成"),
                       isPresented: errorBinding) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(store.errorMessage ?? "")
                }
        }
        .navigationTitle("Trellis")
        .toolbar { toolbar }
        .alert(LocalizedStringKey(store.dialog?.title ?? ""),
               isPresented: dialogBinding) {
            if store.dialog?.hasTextField == true {
                TextField("名称", text: $store.dialogText)
            }
            Button("取消", role: .cancel) { store.dialog = nil }
            if store.dialog?.destructive == true {
                Button(store.dialog?.confirmTitle ?? "确定", role: .destructive) {
                    store.commitDialog()
                }
            } else {
                Button(store.dialog?.confirmTitle ?? "确定") {
                    store.commitDialog()
                }
            }
        } message: {
            Text(store.dialog?.message ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.toast)
        .onAppear {
            keyMonitor.install(store: store)
            #if DEBUG
            if SelfTest.isRequested {
                SelfTest.run(store: store)
            }
            #endif
        }
        .onDisappear {
            keyMonitor.uninstall()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.selectedTemplate != nil {
            HSplitView {
                TemplateEditorView()
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                InspectorView()
                    .frame(minWidth: 306, idealWidth: 330, maxWidth: 380)
            }
        } else {
            WelcomeView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.beginNewTemplate()
            } label: {
                Label("新建模板", systemImage: "plus")
            }
            .help("新建模板（⌘N）")

            Button {
                Actions.importTemplate(store)
            } label: {
                Label("导入模板", systemImage: "square.and.arrow.down")
            }
            .help("从 JSON 导入模板（⌘O）")

            Button {
                Actions.exportSelectedTemplate(store)
            } label: {
                Label("导出模板", systemImage: "square.and.arrow.up")
            }
            .disabled(store.selectedTemplate == nil)
            .help("导出当前模板为 JSON（⌘E）")
        }
    }
}

// MARK: - 欢迎页

struct WelcomeView: View {
    @EnvironmentObject private var store: TemplateStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("Trellis")
                .font(.system(size: 24, weight: .semibold))

            Text("目录模板 · 一键生成项目文件夹")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("把常用的项目目录结构保存成模板，\n选择位置后一键生成完整的项目文件夹。")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("新建模板") { store.beginNewTemplate() }
                    .buttonStyle(.borderedProminent)
                Button("载入示例模板") { store.loadSample() }
            }
            .padding(.top, 6)

            Text("模板保存在本机，不上传任何数据")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

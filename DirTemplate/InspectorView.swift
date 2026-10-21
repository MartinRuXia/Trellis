import SwiftUI
import AppKit

struct InspectorView: View {
    @EnvironmentObject private var store: TemplateStore
    @FocusState private var nameFocused: Bool

    private var template: Template? { store.selectedTemplate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading
                generateCard
                if let created = store.lastCreated {
                    successCard(created)
                }
                if let template {
                    infoCard(template)
                }
                variablesCard
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .simultaneousGesture(TapGesture().onEnded {
            store.deactivateCanvas()
        })
        .onChange(of: store.focusNamePulse) { _, _ in
            nameFocused = true
        }
        .onAppear {
            if store.draftTarget.isEmpty,
               let last = UserDefaults.standard.string(forKey: "lastTargetPath"),
               !last.isEmpty {
                store.draftTarget = last
            }
        }
    }

    // MARK: 标题

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("生成项目")
                .font(.system(size: 15, weight: .semibold))
            Text("选择模板 → 命名 → 选择位置，一键生成")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 生成卡片

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("项目名称")

            HStack(spacing: 6) {
                TextField("例如：20251021 秋日宣传片", text: $store.draftProjectName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($nameFocused)
                    .onSubmit { store.generateNow() }

                Button {
                    pasteName()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("粘贴剪贴板中的项目名称（⌘V）")
            }

            Text("根文件夹名 = 项目名称 · 支持 ⌘C / ⌘V / 右键粘贴")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            if store.trimmedProjectName.isEmpty {
                EmptyView()
            } else if let error = store.nameValidationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else if let issue = store.currentIssues.first {
                Label("\(issue.message)：\(issue.path)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Divider().opacity(0.6)

            fieldLabel("目标位置")

            HStack(alignment: .top, spacing: 8) {
                Text(store.draftTarget.isEmpty ? "未选择" : store.draftTarget)
                    .font(.system(size: 11))
                    .foregroundStyle(store.draftTarget.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("选择…") {
                    if let url = FilePanels.chooseDirectory() {
                        store.draftTarget = url.path
                    }
                }
                .controlSize(.small)
            }

            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("生成预览")
                Text(store.previewPath)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .foregroundStyle(store.draftTarget.isEmpty ? .secondary : .primary)

                if let template {
                    HStack(spacing: 8) {
                        Label("\(template.folderCount) 个文件夹", systemImage: "folder")
                        if !store.currentIssues.isEmpty {
                            Label("\(store.currentIssues.count) 处命名问题", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                    Text(topLevelPreview(template))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Button {
                store.generateNow()
            } label: {
                Label("生成项目", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(template == nil)

            Toggle("生成后显示在 Finder 中", isOn: $store.revealAfterCreate)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
        }
        .cardStyle()
    }

    // MARK: 成功卡片

    private func successCard(_ project: GeneratedProject) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("已生成")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(project.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 4)

            Button("显示") {
                Actions.reveal(project.url)
            }
            .controlSize(.small)
        }
        .cardStyle()
    }

    // MARK: 模板信息

    private func infoCard(_ template: Template) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("模板信息")

            infoRow("名称", template.name)
            infoRow("文件夹", "\(template.folderCount) 个")
            infoRow("层级", "\(template.maxDepth) 级")
            infoRow("更新", template.updatedAt.formatted(date: .numeric, time: .shortened))

            Button {
                Actions.exportSelectedTemplate(store)
            } label: {
                Label("导出模板…", systemImage: "square.and.arrow.up")
                    .font(.system(size: 10))
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .cardStyle()
    }

    // MARK: 变量说明

    private var variablesCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("可在文件夹名称里使用的变量")

            HStack(spacing: 4) {
                token("{项目名}")
                token("{日期}")
                token("{年}")
                token("{月}")
                token("{日}")
            }
            HStack(spacing: 4) {
                token("{yyyyMMdd}")
                token("{时间}")
            }

            Text("生成时会自动替换成当前项目名称和当天日期。例如「{日期} 交付」会变成「2025-10-21 交付」。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: 动作

    private func pasteName() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        store.draftProjectName = cleaned
        nameFocused = true
    }

    // MARK: 小组件

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func token(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.accent.opacity(0.09))
            )
            .foregroundStyle(Theme.accent)
            .textSelection(.enabled)
    }

    private func topLevelPreview(_ template: Template) -> String {
        guard !template.nodes.isEmpty else { return "模板为空，先添加一个根目录" }
        let context = NameContext(projectName: store.trimmedProjectName.isEmpty ? "项目" : store.trimmedProjectName,
                                  date: Date())
        let names = template.nodes.prefix(6).map { DirectoryBuilder.expanded($0.name, context: context) }
        let suffix = template.nodes.count > 6 ? " …" : ""
        return "根目录下：" + names.joined(separator: " · ") + suffix
    }
}

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: TemplateStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("模板库")

                    if store.templates.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("还没有模板")
                                .font(.system(size: 12, weight: .medium))
                            Text("点击左下角「新建模板」开始")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(store.templates) { template in
                            Button {
                                store.deactivateCanvas()
                                store.selectedTemplateID = template.id
                            } label: {
                                TemplateRow(template: template,
                                            selected: store.selectedTemplateID == template.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名模板…") { store.beginRenameTemplate(template) }
                                Button("复制模板") { store.duplicateTemplate(template.id) }
                                Button("导出模板…") {
                                    store.selectedTemplateID = template.id
                                    Actions.exportSelectedTemplate(store)
                                }
                                Divider()
                                Button("删除模板", role: .destructive) {
                                    store.requestDeleteTemplate(template)
                                }
                            }
                        }
                    }

                    if !store.recents.isEmpty {
                        sectionTitle("最近创建")
                        ForEach(store.recents) { project in
                            RecentRow(project: project)
                                .contextMenu {
                                    Button("在 Finder 中显示") { Actions.reveal(project.url) }
                                    Button("重命名文件夹…") { store.beginRenameProject(project) }
                                    Divider()
                                    Button("从列表移除", role: .destructive) { store.removeRecent(project) }
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    store.deactivateCanvas()
                    store.beginNewTemplate()
                } label: {
                    Label("新建模板", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Spacer()

                if let template = store.selectedTemplate {
                    Text("\(template.folderCount) 个文件夹")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Theme.sidebar)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - 模板行

struct TemplateRow: View {
    let template: Template
    let selected: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.folder)

            VStack(alignment: .leading, spacing: 1) {
                Text(template.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(template.folderCount) 个文件夹")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Theme.selection : (hovering ? Theme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - 最近创建行

struct RecentRow: View {
    let project: GeneratedProject

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text(project.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Theme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { Actions.reveal(project.url) }
        .help(project.path)
    }
}

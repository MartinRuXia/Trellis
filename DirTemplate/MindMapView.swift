import SwiftUI
import AppKit

// MARK: - 布局

struct MindMapLayout {
    struct Node: Identifiable {
        let id: UUID
        let name: String
        let depth: Int
        let color: Color
        let center: CGPoint
        let width: CGFloat
        let isRoot: Bool

        var displayName: String {
            if isRoot { return "根节点" }
            return name.isEmpty ? "未命名" : name
        }
    }

    struct Edge: Identifiable {
        let parentID: UUID
        let childID: UUID
        let from: CGPoint
        let to: CGPoint
        let color: Color

        var id: String { "\(parentID)-\(childID)" }
    }

    let nodes: [Node]
    let edges: [Edge]
    let size: CGSize

    static let rootID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    static let palette: [Color] = [
        Color(hex: 0x8B5CF6),
        Color(hex: 0x2E55DB),
        Color(hex: 0x06B6D4),
        Color(hex: 0xF59E0B),
        Color(hex: 0x14B8A6),
        Color(hex: 0x6366F1),
        Color(hex: 0xDB2777),
        Color(hex: 0xEF4444)
    ]

    static func build(template: Template) -> MindMapLayout {
        let nodeWidth: CGFloat = 150
        let rootWidth: CGFloat = 96
        let rowStep: CGFloat = 48
        let levelStep: CGFloat = 206
        let padding: CGFloat = 40
        let rootCenterX: CGFloat = padding + rootWidth / 2
        let levelOneX: CGFloat = rootCenterX + rootWidth / 2 + 76 + nodeWidth / 2

        var nodes: [Node] = []
        var edges: [Edge] = []
        var cursor: CGFloat = 0

        func place(_ node: FolderNode, depth: Int, branch: Int) -> Node {
            var placedChildren: [Node] = []
            for child in node.children {
                placedChildren.append(place(child, depth: depth + 1, branch: branch))
            }

            let y: CGFloat
            if placedChildren.isEmpty {
                y = padding + cursor + rowStep / 2
                cursor += rowStep
            } else {
                y = (placedChildren.first!.center.y + placedChildren.last!.center.y) / 2
            }

            let color = palette[branch % palette.count]
            let centerX = levelOneX + CGFloat(depth - 1) * levelStep
            let model = Node(id: node.id,
                             name: node.name,
                             depth: depth,
                             color: color,
                             center: CGPoint(x: centerX, y: y),
                             width: nodeWidth,
                             isRoot: false)
            nodes.append(model)

            for child in placedChildren {
                edges.append(Edge(parentID: node.id,
                                  childID: child.id,
                                  from: CGPoint(x: centerX + nodeWidth / 2, y: y),
                                  to: CGPoint(x: child.center.x - child.width / 2, y: child.center.y),
                                  color: color))
            }
            return model
        }

        var rootChildren: [Node] = []
        for (index, node) in template.nodes.enumerated() {
            rootChildren.append(place(node, depth: 1, branch: index))
        }

        let rootY: CGFloat
        if rootChildren.isEmpty {
            rootY = padding + rowStep / 2
        } else {
            rootY = (rootChildren.first!.center.y + rootChildren.last!.center.y) / 2
        }

        let root = Node(id: rootID,
                        name: "根节点",
                        depth: 0,
                        color: Color(hex: 0x94A3B8),
                        center: CGPoint(x: rootCenterX, y: rootY),
                        width: rootWidth,
                        isRoot: true)
        nodes.append(root)

        for child in rootChildren {
            edges.append(Edge(parentID: rootID,
                              childID: child.id,
                              from: CGPoint(x: rootCenterX + rootWidth / 2, y: rootY),
                              to: CGPoint(x: child.center.x - child.width / 2, y: child.center.y),
                              color: child.color))
        }

        let maxX = nodes.map { $0.center.x + $0.width / 2 }.max() ?? 0
        let maxY = nodes.map { $0.center.y + 28 }.max() ?? 0
        let size = CGSize(width: max(maxX + padding, 620),
                          height: max(maxY + padding, 460))
        return MindMapLayout(nodes: nodes, edges: edges, size: size)
    }
}

// MARK: - 画布

struct MindMapView: View {
    @EnvironmentObject private var store: TemplateStore
    let template: Template

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        let map = MindMapLayout.build(template: template)

        ZStack {
            DotGridBackground()

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: map.size.width, height: map.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.activateCanvas()
                                store.endEditingFromOutside()
                                store.focusCanvas()
                                store.selectedNodeID = nil
                            }

                        ForEach(map.edges) { edge in
                            LinkCurve(from: edge.from, to: edge.to)
                                .stroke(edge.color.opacity(0.5),
                                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                                .allowsHitTesting(false)
                        }

                        ForEach(map.nodes) { node in
                            MindMapNodeItem(node: node)
                                .position(node.center)
                                .id(node.id)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }

                        editingField(map)
                    }
                    .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
                    .animation(.spring(response: 0.3, dampingFraction: 0.86), value: store.treeRevision)
                    .modifier(ZoomEffect(zoom: zoom))
                    .frame(width: map.size.width * zoom,
                           height: map.size.height * zoom,
                           alignment: .topLeading)
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoom = min(1.8, max(0.5, lastZoom * value))
                            }
                            .onEnded { _ in
                                lastZoom = zoom
                            }
                    )
                }
                .onDeleteCommand {
                    if let id = store.selectedNodeID { store.deleteNode(id) }
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            store.activateCanvas()
        })
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(store.canvasActive ? Theme.accent : Color.clear, lineWidth: 2)
                .padding(6)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.16), value: store.canvasActive)
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .overlay(alignment: .bottom) { emptyHint }
    }

    @ViewBuilder
    private func editingField(_ map: MindMapLayout) -> some View {
        if let editingID = store.editingNodeID,
           let node = map.nodes.first(where: { $0.id == editingID }) {
            InlineNameField(
                nodeID: node.id,
                text: node.name,
                onTextChange: { store.editingText = $0 },
                onCommit: { text, command in
                    store.commitEdit(node.id, text: text, command: command)
                },
                onCancel: {
                    store.cancelEdit(node.id)
                }
            )
            .frame(width: max(110, node.width - 8), height: 24)
            .position(node.center)
        }
    }

    // MARK: 缩放控件

    private var zoomControls: some View {
        HStack(spacing: 8) {
            zoomButton("minus") { zoom = max(0.5, zoom - 0.1); lastZoom = zoom }
            zoomButton("arrow.counterclockwise") { zoom = 1; lastZoom = 1 }
            zoomButton("plus") { zoom = min(1.8, zoom + 0.1); lastZoom = zoom }
        }
        .padding(16)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyHint: some View {
        if template.nodes.isEmpty && store.editingNodeID == nil {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text("按 回车 或点「根节点」右侧的 + 添加第一个文件夹")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.95)))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .padding(.bottom, 24)
        }
    }
}

struct ZoomEffect: ViewModifier {
    let zoom: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if zoom == 1 {
            content
        } else {
            content.scaleEffect(zoom, anchor: .topLeading)
        }
    }
}

// MARK: - 单个节点（悬停状态局部化，避免整图重绘）

struct MindMapNodeItem: View {
    @EnvironmentObject private var store: TemplateStore
    let node: MindMapLayout.Node

    @State private var hovering = false

    private var selected: Bool { store.selectedNodeID == node.id }

    var body: some View {
        MindMapNodeCard(node: node, selected: selected)
            .overlay(alignment: .trailing) {
                if hovering {
                    Button {
                        if node.isRoot {
                            store.beginAddNode(parent: nil)
                        } else {
                            store.beginChild(of: node.id)
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accent)
                            .background(Circle().fill(Color.white).frame(width: 15, height: 15))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 17)
                    .help(node.isRoot ? "新建根文件夹" : "新建子文件夹（Tab）")
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture {
                store.activateCanvas()

                if store.editingNodeID != node.id {
                    store.endEditingFromOutside()
                    // 把焦点从顶部输入框收回来，Tab 才归画布
                    store.focusCanvas()
                }
                guard !node.isRoot else { return }

                // 单击立即选中；已选中的节点再点一次直接进入改名
                if store.selectedNodeID == node.id, store.editingNodeID == nil {
                    store.beginRename(node.id)
                } else {
                    store.selectedNodeID = node.id
                }
            }
            .contextMenu {
                if node.isRoot {
                    Button("新建根文件夹") { store.beginAddNode(parent: nil) }
                } else {
                    Button("新建子文件夹") { store.beginChild(of: node.id) }
                    Button("重命名") { store.beginRename(node.id) }
                    Button("复制（含子目录）") { store.duplicateNode(node.id) }
                    Divider()
                    Button("上移") { store.moveNode(node.id, offset: -1) }
                        .disabled(!store.canMove(node.id, offset: -1))
                    Button("下移") { store.moveNode(node.id, offset: 1) }
                        .disabled(!store.canMove(node.id, offset: 1))
                    Divider()
                    Button("删除", role: .destructive) { store.deleteNode(node.id) }
                }
            }
    }
}

// MARK: - 连线（可动画）

struct LinkCurve: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let dx = max(26, (to.x - from.x) * 0.5)
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + dx, y: from.y),
                      control2: CGPoint(x: to.x - dx, y: to.y))
        return path
    }
}

// MARK: - 节点卡片

struct MindMapNodeCard: View {
    let node: MindMapLayout.Node
    let selected: Bool

    private var filled: Bool { !node.isRoot && node.depth >= 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(filled ? node.color : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: selected ? 2 : 1)
                )
                .shadow(color: selected ? Color.black.opacity(0.16) : Color.clear,
                        radius: selected ? 7 : 0, x: 0, y: 2)

            if node.depth == 1 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(node.color)
                    .frame(width: max(0, node.width - 20), height: 3)
                    .offset(x: 10, y: 4)
            }

            HStack(spacing: 6) {
                Image(systemName: node.isRoot ? "square.grid.2x2.fill" : "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(filled ? Color.white : node.color.opacity(node.isRoot ? 1 : 0.95))

                Text(node.displayName)
                    .font(.system(size: 12, weight: node.isRoot ? .semibold : (node.depth == 1 ? .medium : .regular)))
                    .foregroundStyle(filled ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, node.depth == 1 ? 3 : 0)
            .frame(width: node.width, height: 34, alignment: .leading)
        }
        .frame(width: node.width, height: 34)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var borderColor: Color {
        if selected { return Theme.accent }
        if node.isRoot { return Color.black.opacity(0.12) }
        return node.color.opacity(filled ? 1 : 0.3)
    }
}

// MARK: - 点阵背景

struct DotGridBackground: View {
    var body: some View {
        Image(nsImage: DotPattern.tile)
            .resizable(resizingMode: .tile)
            .background(Color(hex: 0xFBFCFE))
            .ignoresSafeArea()
    }
}

private enum DotPattern {
    static let tile: NSImage = {
        let size = NSSize(width: 26, height: 26)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.withAlphaComponent(0.055).setFill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 1.7, height: 1.7)).fill()
        image.unlockFocus()
        return image
    }()
}

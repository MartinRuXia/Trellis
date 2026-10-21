import Foundation

/// 行内编辑的两种来源：新建（回车连续建同级）或重命名（回车只保存）
enum FolderEditMode {
    case none
    case renaming
    case creating
}

/// 行内编辑提交后要执行的动作
enum FolderEditCommand {
    case sibling
    case child
    case end
}

// MARK: - 目录节点

struct FolderNode: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var children: [FolderNode]

    init(id: UUID = UUID(), name: String, children: [FolderNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    /// 包含自身在内的文件夹数量
    var folderCount: Int { 1 + children.reduce(0) { $0 + $1.folderCount } }

    /// 包含自身在内的层级数
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }

    /// 深拷贝（所有节点使用新的 id）
    func cloned() -> FolderNode {
        FolderNode(id: UUID(), name: name, children: children.map { $0.cloned() })
    }
}

// MARK: - 模板

struct Template: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var nodes: [FolderNode]
    var createdAt: Date
    var updatedAt: Date
    var note: String?

    init(id: UUID = UUID(),
         name: String,
         nodes: [FolderNode] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         note: String? = nil) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }

    var folderCount: Int { nodes.reduce(0) { $0 + $1.folderCount } }
    var maxDepth: Int { nodes.map(\.depth).max() ?? 0 }
}

// MARK: - 生成记录

struct GeneratedProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var templateName: String
    var path: String
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         templateName: String,
         path: String,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.templateName = templateName
        self.path = path
        self.createdAt = createdAt
    }

    var url: URL { URL(fileURLWithPath: path) }
}

// MARK: - 名称变量

struct NameContext {
    var projectName: String
    var date: Date

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "HH-mm"
        return f
    }()

    private var components: DateComponents {
        Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    }

    func expand(_ raw: String) -> String {
        var text = raw
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)

        let map: [String: String] = [
            "{项目名}": projectName,
            "{日期}": Self.dayFormatter.string(from: date),
            "{yyyyMMdd}": Self.stampFormatter.string(from: date),
            "{时间}": Self.timeFormatter.string(from: date),
            "{年}": year,
            "{月}": month,
            "{日}": day
        ]
        for (token, value) in map {
            text = text.replacingOccurrences(of: token, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 树操作

extension Array where Element == FolderNode {
    func node(with id: UUID) -> FolderNode? {
        for node in self {
            if node.id == id { return node }
            if let found = node.children.node(with: id) { return found }
        }
        return nil
    }

    @discardableResult
    mutating func mutateNode(_ id: UUID, _ body: (inout FolderNode) -> Void) -> Bool {
        for index in indices {
            if self[index].id == id {
                body(&self[index])
                return true
            }
            if self[index].children.mutateNode(id, body) { return true }
        }
        return false
    }

    @discardableResult
    mutating func removeNode(_ id: UUID) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            remove(at: index)
            return true
        }
        for index in indices {
            if self[index].children.removeNode(id) { return true }
        }
        return false
    }

    @discardableResult
    mutating func insertAfter(_ id: UUID, node: FolderNode) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            insert(node, at: index + 1)
            return true
        }
        for index in indices {
            if self[index].children.insertAfter(id, node: node) { return true }
        }
        return false
    }

    func parentID(of id: UUID) -> UUID? {
        for node in self {
            if node.children.contains(where: { $0.id == id }) { return node.id }
            if let parent = node.children.parentID(of: id) { return parent }
        }
        return nil
    }

    @discardableResult
    mutating func moveNode(_ id: UUID, offset: Int) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            let target = index + offset
            guard indices.contains(target) else { return false }
            let node = remove(at: index)
            insert(node, at: target)
            return true
        }
        for index in indices {
            if self[index].children.moveNode(id, offset: offset) { return true }
        }
        return false
    }

    func canMoveNode(_ id: UUID, offset: Int) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            return indices.contains(index + offset)
        }
        for node in self {
            if node.children.canMoveNode(id, offset: offset) { return true }
        }
        return false
    }

    func allIDs() -> [UUID] {
        flatMap { [$0.id] + $0.children.allIDs() }
    }
}

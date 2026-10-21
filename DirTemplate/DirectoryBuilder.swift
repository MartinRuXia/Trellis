import Foundation

/// 纯 Foundation 的目录生成引擎，方便单独做命令行测试。
enum DirectoryBuilder {

    struct Issue: Identifiable, Hashable {
        let id = UUID()
        let path: String
        let message: String
    }

    // MARK: 校验

    /// 返回 nil 表示名称合法；否则返回给用户看的原因。
    static func validateName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "名称不能为空" }
        if name.contains("/") { return "名称不能包含 “/”" }
        if name.contains(":") { return "名称不能包含 “:”" }
        if name.hasPrefix(".") { return "名称不能以 “.” 开头" }
        if name.utf8.count > 255 { return "名称过长（超过 255 字节）" }
        if name == "." || name == ".." { return "名称无效" }
        return nil
    }

    static func expanded(_ raw: String, context: NameContext) -> String {
        context.expand(raw)
    }

    /// 检查整棵模板树：非法名称、同级重名。返回的路径用于定位问题节点。
    static func issues(nodes: [FolderNode], context: NameContext) -> [Issue] {
        var result: [Issue] = []

        func walk(_ list: [FolderNode], parentPath: String) {
            var seen: [String: UUID] = [:]
            for node in list {
                let name = expanded(node.name, context: context)
                let path = parentPath + name
                if let error = validateName(name) {
                    result.append(Issue(path: path, message: error))
                }
                if seen[name] != nil {
                    result.append(Issue(path: path, message: "同级目录中存在重名文件夹"))
                } else {
                    seen[name] = node.id
                }
                walk(node.children, parentPath: path + "/")
            }
        }

        walk(nodes, parentPath: "")
        return result
    }

    /// 生成后会在磁盘上出现的所有相对路径（含根目录名）。
    static func plannedPaths(nodes: [FolderNode], rootName: String, context: NameContext) -> [String] {
        var result: [String] = [rootName]

        func walk(_ list: [FolderNode], prefix: String) {
            for node in list {
                let name = expanded(node.name, context: context)
                let path = prefix.isEmpty ? name : prefix + "/" + name
                result.append(path)
                walk(node.children, prefix: path)
            }
        }

        walk(nodes, prefix: rootName)
        return result
    }

    // MARK: 创建

    /// 在 `root` 处创建根目录，并按模板创建下一级目录。
    /// 任何一步失败都会抛出带路径信息的错误。
    @discardableResult
    static func create(nodes: [FolderNode], at root: URL, context: NameContext) throws -> [URL] {
        let fm = FileManager.default
        var created: [URL] = []

        func makeDirectory(_ url: URL) throws {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                created.append(url)
            } catch {
                throw BuildFailure(path: url.path, underlying: error)
            }
        }

        try makeDirectory(root)

        func walk(_ list: [FolderNode], base: URL) throws {
            for node in list {
                let name = expanded(node.name, context: context)
                let url = base.appendingPathComponent(name, isDirectory: true)
                try makeDirectory(url)
                try walk(node.children, base: url)
            }
        }

        try walk(nodes, base: root)
        return created
    }

    /// 找同目录下不冲突的名称：项目 → 项目 2 → 项目 3 …
    static func uniqueName(_ base: String, in parent: URL) -> String {
        let fm = FileManager.default
        var candidate = base
        var index = 2
        while fm.fileExists(atPath: parent.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(index)"
            index += 1
            if index > 999 { break }
        }
        return candidate
    }
}

// MARK: - 错误

struct BuildFailure: LocalizedError {
    let path: String
    let underlying: Error

    var errorDescription: String? {
        let nsError = underlying as NSError
        switch nsError.code {
        case NSFileWriteNoPermissionError:
            return "没有写入权限：\(path)\n请换一个位置，或在「系统设置 → 隐私与安全性 → 文件与文件夹」中授权。"
        case NSFileWriteFileExistsError:
            return "已存在同名项目：\(path)"
        case NSFileWriteOutOfSpaceError:
            return "磁盘空间不足：\(path)"
        default:
            return "创建文件夹失败：\(path)\n\(underlying.localizedDescription)"
        }
    }
}

struct StoreError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

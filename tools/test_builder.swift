import Foundation

// 轻量级命令行测试：直接编译 Models.swift + DirectoryBuilder.swift 运行。

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

print("1) 名称校验")
check(DirectoryBuilder.validateName("素材") == nil, "正常名称通过")
check(DirectoryBuilder.validateName("a/b") != nil, "拒绝 /")
check(DirectoryBuilder.validateName("a:b") != nil, "拒绝 :")
check(DirectoryBuilder.validateName("   ") != nil, "拒绝空白")
check(DirectoryBuilder.validateName(".hidden") != nil, "拒绝点开头")

print("2) 变量替换")
var components = DateComponents()
components.year = 2025
components.month = 3
components.day = 7
let date = Calendar(identifier: .gregorian).date(from: components)!
let context = NameContext(projectName: "春日宣传片", date: date)
check(context.expand("{项目名} 素材") == "春日宣传片 素材", "项目名")
check(context.expand("{日期} 交付") == "2025-03-07 交付", "日期")
check(context.expand("{yyyyMMdd}") == "20250307", "yyyyMMdd")
check(context.expand("{年}年{月}月{日}日") == "2025年03月07日", "年月日")

print("3) 同级重名与非法名称检测")
let duplicated = [
    FolderNode(name: "素材"),
    FolderNode(name: "素材"),
    FolderNode(name: "a/b")
]
let issues = DirectoryBuilder.issues(nodes: duplicated, context: context)
check(issues.count == 2, "检出 1 个重名 + 1 个非法（实际 \(issues.count)）")

print("4) 真实创建目录")
let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("DirTemplateTest-\(UUID().uuidString)")
let templateNodes = [
    FolderNode(name: "01 素材", children: [
        FolderNode(name: "视频"),
        FolderNode(name: "音频")
    ]),
    FolderNode(name: "{日期} 交付")
]
do {
    let created = try DirectoryBuilder.create(nodes: templateNodes, at: root, context: context)
    let fm = FileManager.default
    check(created.count == 5, "创建 5 个文件夹（实际 \(created.count)）")
    check(fm.fileExists(atPath: root.appendingPathComponent("01 素材/视频").path), "嵌套目录存在")
    check(fm.fileExists(atPath: root.appendingPathComponent("2025-03-07 交付").path), "变量目录已展开")
    check(!fm.fileExists(atPath: root.appendingPathComponent("{日期} 交付").path), "没有残留原始占位符")

    let planned = DirectoryBuilder.plannedPaths(nodes: templateNodes, rootName: "项目A", context: context)
    check(planned.count == 5, "计划路径含根目录共 5 条（实际 \(planned.count)）")
} catch {
    failures += 1
    print("  ✗ 创建失败：\(error.localizedDescription)")
}
try? FileManager.default.removeItem(at: root)

print("5) 同名自动编号")
let uniqueRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("DirTemplateUnique-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: uniqueRoot.appendingPathComponent("项目"), withIntermediateDirectories: true)
let suggestion = DirectoryBuilder.uniqueName("项目", in: uniqueRoot)
check(suggestion == "项目 2", "同名时建议「项目 2」（实际 \(suggestion)）")
try? FileManager.default.removeItem(at: uniqueRoot)

print("")
if failures == 0 {
    print("全部通过 ✅")
    exit(0)
} else {
    print("失败 \(failures) 项 ❌")
    exit(1)
}

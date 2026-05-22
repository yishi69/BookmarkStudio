# 01 — 项目概览

## Bookmark Studio 是什么

一个 **Visual Studio 扩展**，用于在代码编辑器中标记、组织和快速跳转到重要代码位置。比 VS 自带的书签功能更强大，支持颜色标记、文件夹分组、跨解决方案共享、全局书签等。

核心功能：
- **彩色书签**：8 种颜色标记代码行，在编辑器边栏显示色块
- **快捷键跳转**：Alt+Shift+1~9 直接跳到编号书签
- **文件夹管理**：拖拽分组，树形结构组织书签
- **三种存储位置**：Global（全局跨方案）、Personal（.vs 目录）、Workspace（方案根目录，团队共享）
- **搜索过滤**：按名称、文件、颜色、行文本搜索
- **内置命令拦截**：可接管 VS 原生书签快捷键（Ctrl+K, Ctrl+K）

## 技术栈

| 层级 | 技术 |
|------|------|
| 目标框架 | .NET Framework 4.8 |
| UI 框架 | WPF (XAML) |
| VS SDK | Microsoft.VSSDK.BuildTools |
| 核心库 | Community.VisualStudio.Toolkit.17 |
| 测试 | MSTest |
| 序列化 | System.Text.Json |
| 语言 | C# (latest) + Nullable enabled |

## 关键依赖

```
Community.VisualStudio.Toolkit.17  — 社区封装的 VS SDK，简化扩展开发
Microsoft.VSSDK.BuildTools         — 官方 VS 扩展构建工具（含 VSCT 编译等）
System.Text.Json                   — JSON 序列化（读写 .bookmarks.json）
```

## 数据存储

书签持久化到 JSON 文件：

| 存储位置 | 路径 | 用途 |
|----------|------|------|
| Global | `%USERPROFILE%\.bookmarks.json` | 跨方案持久化 |
| Personal | `.vs\.bookmarks.json` | 用户私有 |
| Workspace | 方案根目录或仓库根目录 `.bookmarks.json` | 团队共享 |

JSON 结构示例：
```json
{
  "documentPathRoot": "bookmarksFile",
  "root": {
    "_bookmarks": [
      {
        "id": "abc123...",
        "documentPath": "src/App/Program.cs",
        "lineNumber": 42,
        "lineText": "public static void Main()",
        "slotNumber": 1,
        "label": "Entry Point",
        "color": "blue"
      }
    ],
    "MyFolder": {
      "_bookmarks": [ ... ]
    }
  }
}
```

## 版本

当前版本 `1.0.902`，作者 Mads Kristensen，支持 Visual Studio 17.0+ (VS 2022)。

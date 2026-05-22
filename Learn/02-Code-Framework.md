# 02 — 代码框架

## 目录结构

```
BookmarkStudio/
├── BookmarkStudio.slnx              # 解决方案文件
├── setup.ps1                        # 一键构建脚本
├── src/
│   ├── BookmarkStudio.csproj        # 项目文件（VSIX 配置在此）
│   ├── BookmarkStudioPackage.cs     # ★ 扩展入口点
│   ├── source.extension.vsixmanifest # VSIX 清单（扩展元数据）
│   ├── source.extension.cs          # 自动生成（Vsix 常量）
│   ├── VSCommandTable.vsct          # ★ 命令/菜单/快捷键定义
│   ├── VSCommandTable.cs            # 自动生成（命令 ID 常量）
│   ├── Monikers.imagemanifest       # 自定义图标清单
│   ├── Commands/                    # 所有命令处理类
│   │   ├── BookmarkCommandBase.cs         # 命令基类
│   │   ├── ToggleBookmarkCommand.cs       # 切换书签
│   │   ├── AddBookmarkCommand.cs         # 添加书签
│   │   ├── GoToNextBookmarkCommand.cs    # 下一个书签
│   │   ├── GoToPreviousBookmarkCommand.cs # 上一个书签
│   │   ├── GoToShortcutCommands.cs       # 跳转快捷键 1-9
│   │   ├── OpenBookmarkManagerCommand.cs  # 打开管理器窗口
│   │   ├── BookmarkCommandActions.cs     # 命令执行的统一入口
│   │   ├── BookmarkBuiltInCommandInterceptor.cs  # ★ 拦截 VS 原生命令
│   │   ├── SortByCommands.cs / GroupByCommands.cs / FilterByColorCommands.cs
│   │   └── ...更多命令
│   ├── Services/                    # 业务逻辑服务层
│   │   ├── BookmarkModels.cs              # 数据模型（Bookmark, Snapshot等）
│   │   ├── BookmarkMetadataStore.cs       # ★ JSON 文件读写（数据持久化）
│   │   ├── BookmarkRepositoryService.cs   # 书签 CRUD 操作
│   │   ├── BookmarkStudioSession.cs       # ★ 全局会话（缓存、协调）
│   │   ├── BookmarkOperationsService.cs   # ★ 高级操作（导航、切换、标签建议）
│   │   ├── BookmarkRefreshMonitorService.cs # 文件变更监听（重命名/删除）
│   │   └── BookmarkNameSuggestionService.cs # 智能命名建议
│   ├── ToolWindows/                 # 书签管理器 UI
│   │   ├── BookmarkManagerToolWindow.cs   # 工具窗口定义
│   │   ├── BookmarkManagerControl.xaml    # ★ WPF 界面（TreeView+样式）
│   │   ├── BookmarkManagerControl.xaml.cs # 界面事件处理
│   │   ├── BookmarkManagerViewModel.cs   # ★ ViewModel（数据绑定、树构建）
│   │   └── BookmarkSortGroupModes.cs     # 排序/分组模式枚举
│   ├── Editor/                      # 编辑器边栏集成
│   │   ├── BookmarkGlyphTagger.cs         # 在边栏显示书签色块
│   │   ├── BookmarkGlyphFactory.cs        # 色块渲染
│   │   ├── BookmarkGlyphMouseProcessor.cs # 边栏拖拽/点击处理
│   │   └── BookmarkTextBufferTracking.cs  # 文本变更追踪（行号同步）
│   ├── Options/                     # 选项页
│   │   └── General.cs                     # Tools > Options 配置
│   ├── Helpers/                     # 辅助工具
│   │   ├── BookmarkContextMenuHelper.cs   # 右键菜单构建
│   │   ├── NativeBookmarkHelper.cs        # VS 原生书签交互
│   │   └── ThemedContextMenuHelper.cs     # 主题化上下文菜单
│   ├── Dialogs/                     # 对话框
│   │   └── TextPromptWindow.cs            # 文本输入对话框
│   └── Resources/                   # 图标资源
│       └── BookmarkColors/               # 8 种颜色图标 PNG
└── test/
    └── BookmarkStudio.Test/         # 单元测试
        ├── BookmarkStudio.Test.csproj
        ├── BookmarkManagerViewModelTests.cs
        ├── RepositoryAndModelTests.cs
        ├── BookmarkMetadataStoreTests.cs
        └── ...更多测试
```

## 三层架构

```
┌─────────────────────────────────────────────┐
│                   UI 层                      │
│  ToolWindows/ (XAML + ViewModel)             │
│  Editor/    (Glyph 边栏渲染)                 │
│  Commands/  (命令触发入口)                   │
│  Dialogs/   (文本输入对话框)                 │
├─────────────────────────────────────────────┤
│                 服务层                       │
│  BookmarkOperationsService   （高级操作）    │
│  BookmarkStudioSession       （会话协调）    │
│  BookmarkRepositoryService   （CRUD）        │
│  BookmarkRefreshMonitorService（文件监听）   │
│  BookmarkNameSuggestionService（智能建议）   │
├─────────────────────────────────────────────┤
│                 数据层                       │
│  BookmarkMetadataStore      （JSON 读写）    │
│  BookmarkModels             （数据模型）     │
│  Options/General            （配置模型）     │
└─────────────────────────────────────────────┘
```

数据流方向：**Commands → OperationsService → Session → RepositoryService → MetadataStore → JSON 文件**

## 架构关键决策：三种存储位置

这是这个项目最有意思的设计之一。书签可以存三个地方，运行时合并显示：

```
DualBookmarkWorkspaceState
├── GlobalState    （%USERPROFILE%\.bookmarks.json）
├── PersonalState  （.vs\.bookmarks.json）
└── SolutionState  （仓库根\.bookmarks.json）

三者合并 → AllBookmarks (IReadOnlyList<ManagedBookmark>)
快捷键冲突解决：SolutionState > PersonalState > GlobalState
```

## 核心类详解

### 1. 入口点 — `BookmarkStudioPackage.cs`

```csharp
[PackageRegistration(...)]                    // 注册包
[ProvideMenuResource("Menus.ctmenu", 1)]      // 关联命令表
[ProvideToolWindow(...)]                      // 注册工具窗口
[ProvideOptionPage(...)]                      // 注册选项页
[ProvideAutoLoad(...)]                        // 自动加载条件
public sealed class BookmarkStudioPackage : ToolkitPackage
```

启动流程：
1. 注册工具窗口 → `this.RegisterToolWindows()`
2. 启动文件监听 → `BookmarkRefreshMonitorService.Instance.InitializeAsync()`
3. 注册所有命令 → `this.RegisterCommandsAsync()`
4. 拦截 VS 内置命令 → `BookmarkBuiltInCommandInterceptor.InitializeAsync()`
5. 订阅解决方案事件 → `OnAfterOpenSolution` 等
6. 空闲时首次刷新 → `StartOnIdle(...RefreshAsync...)`

### 2. 数据模型 — `BookmarkModels.cs`

```
BookmarkSnapshot      — 快照（文档路径+行号+行文本），用于创建/查找
BookmarkMetadata      — 持久化模型（含 Id、Color、Label、Shortcut 等）
ManagedBookmark       — 展示模型（含计算属性 FileName、RepositoryRelativePath）
BookmarkWorkspaceState — 单个存储位置的状态（书签列表+文件夹集合）
DualBookmarkWorkspaceState — 三个存储位置的合并视图
```

关键设计：
- `BookmarkIdentity` 工具类处理路径规范化、精确匹配 Key 生成
- `ExactMatchKey = "标准化路径|行号"` 用于判断书签是否已存在

### 3. 持久化 — `BookmarkMetadataStore.cs`

负责 JSON 文件的读写，核心方法：

```
LoadWorkspaceFromLocationAsync()   — 从指定存储位置加载
SaveWorkspaceToLocationAsync()     — 保存到指定存储位置
LoadDualWorkspaceAsync()           — 同时加载三个位置
MoveToLocationAsync()              — 整体迁移存储位置
MoveBookmarkBetweenLocationsAsync() — 单个书签迁移
MoveFolderBetweenLocationsAsync()  — 文件夹跨存储迁移
```

JSON 解析：递归解析 `root` 对象中的文件夹树，每个文件夹节点可包含 `_bookmarks` 数组和子文件夹。

路径处理：
- Workspace 模式下路径相对于 `.bookmarks.json` 所在目录（可移植）
- Personal/Global 模式下路径相对于解决方案目录

### 4. 全局会话 — `BookmarkStudioSession.cs`

单例模式，维护内存缓存和线程安全：

```
CachedBookmarks     — 当前可见的书签列表
CachedDualState     — 三个存储位置的缓存状态
CachedFolderPaths   — 所有已知文件夹路径
BookmarksChanged    — 数据变更事件（通知 UI 刷新）

核心操作：
  RefreshAsync()     — 从磁盘重新加载
  UpdateBookmarksAsync() — 修改后保存
  ToggleBookmarkAsync()  — 切换书签（核心操作，跨三个存储位置查找）
  MoveBookmarkToStorageAsync() — 跨存储移动
```

线程安全：所有写操作通过 `SemaphoreSlim _repositoryGate` 串行化。

### 5. 高级操作 — `BookmarkOperationsService.cs`

面向 UI 和命令的高级 API：

```
ToggleBookmarkAsync()    — 创建/删除书签
NavigateToBookmarkAsync() — 跳转到书签位置
GoToNextBookmarkAsync()  — 导航到下一个
AssignShortcutAsync()    — 分配快捷键编号
SetColorAsync()          — 设置颜色
RenameLabelAsync()       — 重命名标签
CreateFolderAsync()      — 创建文件夹
MoveBookmarkToFolderAsync() — 移动书签到文件夹
GetSuggestedLabelAsync() — 智能命名建议
```

导航逻辑 (`NavigateToBookmarkCoreAsync`)：
1. 检查文件是否存在（不存在则弹窗询问是否删除）
2. 通过 DTE Automation 打开文件
3. 移动光标到目标行

### 6. 书签管理器 ViewModel — `BookmarkManagerViewModel.cs`

这个类是整个 UI 的核心，约 1700 行：

**数据维护**：维护三份独立的书签列表和文件夹集合
- `_globalBookmarks` / `_globalFolderPaths`
- `_personalBookmarks` / `_personalFolderPaths`
- `_solutionBookmarks` / `_solutionFolderPaths`

**树形结构构建** (`RebuildTree`)：
1. 为每个存储位置构建独立的根节点
2. `Global` 节点始终显示（跨方案可见）
3. `User` (Personal) 和 `Workspace` 节点仅在方案打开时显示
4. 每个根节点下按文件夹层次递归构建树

**搜索/过滤/排序/分组**：
- 搜索：在 Label、FileName、DocumentPath、LineText 中匹配
- 过滤：按颜色过滤
- 排序：Alphabetical / LineNumber / Slot / Created 四种模式
- 分组：Folders（树形）/ Color / File 三种模式

**多选支持**：Ctrl+Click 多选书签/文件夹，批量设置颜色、删除

**ViewModel 层级**：
```
BookmarkNodeViewModel (抽象)
├── FolderNodeViewModel      — 文件夹节点（含 IsExpanded, Children）
└── BookmarkItemNodeViewModel — 书签节点（含 Bookmark, TreeDepth）

BookmarkGridRowViewModel     — 搜索模式下扁平展示用
```

### 7. 工具窗口 — `BookmarkManagerToolWindow.cs`

```csharp
internal sealed class BookmarkManagerToolWindow : BaseToolWindow<BookmarkManagerToolWindow>
{
    public override string GetTitle(int toolWindowId) => "Bookmark Manager";
    public override Type PaneType => typeof(Pane);
    public override async Task<FrameworkElement> CreateAsync(...) => new BookmarkManagerControl();
}
```

内嵌的 `Pane` 类提供：
- 工具栏集成 (`ToolBar` 属性关联 VSCT 定义的工具栏)
- VS 搜索框集成 (`SearchEnabled = true` + `CreateSearch`)

### 8. 命令表 — `VSCommandTable.vsct`

定义所有命令、菜单、工具栏、快捷键。关键结构：

```
<Commands>
  <Groups>     — 命令组（决定按钮放在哪个菜单/工具栏的哪个位置）
  <Menus>      — 菜单/子菜单/工具栏定义
  <Buttons>    — 按钮定义（关联图标、文字、父组）
</Commands>
<KeyBindings>  — 快捷键绑定
<CommandPlacements> — 命令放置（同一个命令可以出现在多个位置）
<Symbols>      — GUID/ID 常量定义
```

例如 "Toggle Bookmark" 按钮：
```xml
<Button guid="BookmarkStudio" id="ToggleBookmarkCommand" type="Button">
  <Icon guid="ImageCatalogGuid" id="Bookmark" />
  <Strings>
    <ButtonText>Toggle Bookmark</ButtonText>
  </Strings>
</Button>
```

快捷键：
```xml
<KeyBinding id="ToggleBookmarkCommand" key1="VK_SPACE" mod1="Alt Shift" />
```

### 9. 命令执行模式

所有命令遵循 Community Toolkit 的模式：

```csharp
[Command(PackageIds.ToggleBookmarkCommand)]  // 关联 VSCT 定义的命令 ID
internal sealed class ToggleBookmarkCommand : BookmarkCommandBase<ToggleBookmarkCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
        => await BookmarkCommandActions.ToggleBookmarkAsync(...);

    protected override void BeforeQueryStatus(EventArgs e)
    {
        Command.Enabled = ...;  // 控制命令是否可用
    }
}
```

`BookmarkCommandActions` 是命令逻辑的统一入口，将命令路由到 `BookmarkOperationsService`。

### 10. 内置命令拦截 — `BookmarkBuiltInCommandInterceptor.cs`

通过 `VS.Commands.InterceptAsync()` 拦截 VS 原生书签命令：

| VS 原生命令 | 拦截后的行为 |
|-------------|-------------|
| `Ctrl+K, Ctrl+K` (ToggleBookmark) | 创建 BookmarkStudio 书签 |
| `Ctrl+K, Ctrl+N` (NextBookmark) | 跳转到下一个 BookmarkStudio 书签 |
| `Ctrl+K, Ctrl+P` (PrevBookmark) | 跳转到上一个 |
| `Ctrl+Shift+K, Ctrl+Shift+N` | 文档内下一个 |
| `Ctrl+Shift+K, Ctrl+Shift+P` | 文档内上一个 |
| `Ctrl+Shift+K, Ctrl+Shift+L` | 清除文档内所有 |

拦截策略（通过选项配置）：
- **Ask**（默认）：首次使用时弹窗询问
- **Yes**：始终拦截
- **No**：不拦截，原生书签正常工作

### 11. 文件监听 — `BookmarkRefreshMonitorService.cs`

实现 `IVsTrackProjectDocumentsEvents2` 接口：

```
OnAfterRemoveFiles  → 删除书签（文件被删了，书签也没意义）
OnAfterRenameFiles  → 更新书签中的文件路径
```

## 文件间依赖关系总结

```
BookmarkStudioPackage (入口)
  ├── 注册 → VSCommandTable.vsct (命令定义)
  ├── 注册 → BookmarkManagerToolWindow (工具窗口)
  ├── 启动 → BookmarkRefreshMonitorService (文件监听)
  ├── 启动 → BookmarkBuiltInCommandInterceptor (命令拦截)
  └── 事件 → 解决方案打开/关闭 → BookmarkStudioSession.RefreshAsync()

用户点击命令按钮
  → Commands/* → BookmarkCommandActions
  → BookmarkOperationsService
  → BookmarkStudioSession (缓存+协调)
  → BookmarkRepositoryService (CRUD)
  → BookmarkMetadataStore (JSON读写)
  → .bookmarks.json 文件

UI 刷新
  → BookmarkManagerToolWindow.RefreshAsync()
  → 触发 Session.RefreshAsync()
  → BookmarkManagerViewModel.RefreshAsync()
  → RebuildTree() → 更新 TreeView/DataGrid
```

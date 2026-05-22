# 03 — VS 扩展核心概念

本文通过 BookmarkStudio 的实际代码，解释 Visual Studio 扩展开发中最核心的几个概念。

---

## 1. Package — 扩展的"身份证"

每个 VS 扩展有且只有一个 Package 类，它继承自 `AsyncPackage` 或社区版 `ToolkitPackage`：

```csharp
// src/BookmarkStudioPackage.cs
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration(Vsix.Name, Vsix.Description, Vsix.Version)]
[Guid(PackageGuids.BookmarkStudioString)]
public sealed class BookmarkStudioPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(...)
    {
        // 在这里做所有初始化工作
    }
}
```

**关键 Attribute 含义**：

| Attribute | 作用 |
|-----------|------|
| `[PackageRegistration]` | 告诉 VS 这是一个扩展包，`AllowsBackgroundLoading=true` 表示支持后台加载（提升 VS 启动速度） |
| `[ProvideMenuResource]` | 关联命令表资源（Menus.ctmenu 来自 VSCT 编译产物） |
| `[ProvideToolWindow]` | 声明此扩展提供一个工具窗口 |
| `[ProvideOptionPage]` | 声明此扩展在 Tools > Options 中有配置页 |
| `[ProvideAutoLoad]` | 指定什么条件下自动加载此扩展（如方案打开时） |
| `[ProvideBindingPath]` | 告诉 VS 在哪里查找扩展的 DLL 依赖 |

---

## 2. VSCT — 命令、菜单和快捷键的定义

`VSCommandTable.vsct` 是一个 XML 文件，编译后生成 C# 常量（`VSCommandTable.cs`）和二进制命令表（`.cto` 文件）。

**核心概念**：

```
GuidSymbol  →  命令组标识（GUID）
IDSymbol    →  命令 ID（数字）
Group       →  命令组（决定按钮放在哪里）
Menu        →  菜单/子菜单/工具栏
Button      →  按钮（关联到命令处理类）
KeyBinding  →  键盘快捷键
```

**命令组的父子关系决定菜单布局**：

```xml
<!-- 定义一个工具栏 -->
<Menu guid="BookmarkStudio" id="BookmarkManagerToolbar" type="ToolWindowToolbar" />

<!-- 工具栏上的分组（按 priority 排序） -->
<Group guid="BookmarkStudio" id="RefreshGroup"  priority="0x0000">
  <Parent guid="BookmarkStudio" id="BookmarkManagerToolbar"/>
</Group>
<Group guid="BookmarkStudio" id="NewItemsGroup" priority="0x0100">
  <Parent guid="BookmarkStudio" id="BookmarkManagerToolbar"/>
</Group>

<!-- 按钮放在哪个组里 -->
<Button guid="BookmarkStudio" id="RefreshCommand" priority="0x0100" type="Button">
  <Parent guid="BookmarkStudio" id="RefreshGroup"/>
  <Icon guid="ImageCatalogGuid" id="Refresh"/>
  <Strings>
    <ButtonText>Refresh</ButtonText>
  </Strings>
</Button>
```

**插入 VS 内置菜单**：

```xml
<!-- 插入到编辑器右键菜单 -->
<Group guid="BookmarkStudio" id="EditorContextGroup" priority="0x0700">
  <Parent guid="guidSHLMainMenu" id="IDM_VS_CTXT_CODEWIN"/>
</Group>

<!-- 插入到编辑器左侧边栏右键菜单 -->
<Group guid="BookmarkStudio" id="MarginContextGroup" priority="0x0100">
  <Parent guid="guidEditorCommands" id="LeftMarginContextMenu"/>
</Group>
```

**快捷键绑定**：

```xml
<KeyBinding guid="BookmarkStudio" id="ToggleBookmarkCommand"
            editor="guidVSStd97" key1="VK_SPACE" mod1="Alt Shift" />
```

- `editor="guidVSStd97"` — 全局快捷键
- `editor="GUID_TextEditorFactory"` — 仅在文本编辑器中生效

---

## 3. Command — 处理用户操作

Community Toolkit 的命令模式：

```csharp
// src/Commands/ToggleBookmarkCommand.cs
[Command(PackageIds.ToggleBookmarkCommand)]  // 关联 VSCT 中定义的 ID
internal sealed class ToggleBookmarkCommand : BookmarkCommandBase<ToggleBookmarkCommand>
{
    // 点击按钮时执行
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
        => await BookmarkCommandActions.ToggleBookmarkAsync(CancellationToken.None);

    // 每次 UI 刷新时调用，控制按钮的可用/可见状态
    protected override void BeforeQueryStatus(EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        Command.Enabled = BookmarkOperationsService.Current.CanToggleBookmarkInActiveDocument();
    }
}
```

**重要模式**：`Command.Enabled` — 没有打开文档时按钮自动灰掉，不需要手动控制。

**命令不在 VSCT 中指定 Parent 时**，可以通过 `CommandPlacement` 放置到多个位置：

```xml
<CommandPlacement guid="BookmarkStudio" id="OpenBookmarkManagerCommand" priority="0x0100">
  <Parent guid="BookmarkStudio" id="BookmarkShortcutsMenuGroup"/>
</CommandPlacement>
<CommandPlacement guid="BookmarkStudio" id="OpenBookmarkManagerCommand" priority="0x0100">
  <Parent guid="BookmarkStudio" id="EditorContextBookmarkManagerGroup"/>
</CommandPlacement>
```

---

## 4. ToolWindow — 自定义面板

```csharp
// src/ToolWindows/BookmarkManagerToolWindow.cs
internal sealed class BookmarkManagerToolWindow : BaseToolWindow<BookmarkManagerToolWindow>
{
    public override string GetTitle(int toolWindowId) => "Bookmark Manager";

    public override Type PaneType => typeof(Pane);

    // 创建工具窗口的 UI 内容
    public override async Task<FrameworkElement> CreateAsync(int toolWindowId, CancellationToken ct)
    {
        _currentControl = new BookmarkManagerControl();
        return _currentControl;
    }

    // 内嵌 Pane 类提供高级功能
    [Guid("0bad4445-cbc4-4567-be7e-2b962807614b")]
    internal sealed class Pane : ToolWindowPane
    {
        public Pane()
        {
            BitmapImageMoniker = KnownMonikers.StatusInformation;  // 标签页图标
            ToolBar = new CommandID(PackageGuids.BookmarkStudio, PackageIds.BookmarkManagerToolbar);
            ToolBarLocation = (int)VSTWT_LOCATION.VSTWT_TOP;  // 工具栏在顶部
        }

        public override bool SearchEnabled => true;  // 启用 VS 搜索框

        public override IVsSearchTask CreateSearch(...)
        {
            return new BookmarkManagerSearchTask(...);
        }
    }
}
```

在 Package 中注册工具窗口：

```csharp
// 在 BookmarkStudioPackage 的 Attribute 中
[ProvideToolWindow(typeof(BookmarkManagerToolWindow.Pane),
    Style = VsDockStyle.Tabbed,
    Window = WindowGuids.SolutionExplorer)]  // 默认停靠在 Solution Explorer 旁边
```

---

## 5. Options — 配置页

```csharp
// src/Options/General.cs
internal class General : BaseOptionModel<General>
{
    [Category("Bookmarks")]
    [DisplayName("Prompt for bookmark name")]
    [Description("When enabled, a dialog will prompt for a name...")]
    [DefaultValue(false)]
    public bool PromptForBookmarkName { get; set; }

    [Category("Commands")]
    [DisplayName("Intercept built-in bookmark commands")]
    [DefaultValue(CommandInterceptionMode.Ask)]
    public CommandInterceptionMode InterceptBuiltInCommands { get; set; }
}
```

配置在 Package 的 Attribute 中注册：
```csharp
[ProvideOptionPage(typeof(OptionsProvider.GeneralOptions), "Bookmark Studio", "General", ...)]
```

使用配置：
```csharp
// 读取
bool prompt = General.Instance.PromptForBookmarkName;

// 保存
General.Instance.PromptForBookmarkName = false;
await General.Instance.SaveAsync();

// 监听变更
General.Saved += OnSettingsSaved;
```

---

## 6. MEF — 编辑器扩展的依赖注入

在 VS 编辑器中添加功能（如边栏色块）需要通过 MEF (Managed Extensibility Framework) 导出组件：

```csharp
// src/Editor/BookmarkGlyphTaggerProvider.cs
[Export(typeof(ITaggerProvider))]           // 导出为 ITaggerProvider
[ContentType("text")]                       // 适用于所有文本文件
[TagType(typeof(BookmarkGlyphTag))]         // 产生的 Tag 类型
internal sealed class BookmarkGlyphTaggerProvider : ITaggerProvider
{
    public ITagger<T> CreateTagger<T>(ITextBuffer buffer) where T : ITag
    {
        return new BookmarkGlyphTagger(buffer) as ITagger<T>;
    }
}
```

VS 编辑器扩展的关键接口：

| 接口 | 作用 | 本项目中的实现 |
|------|------|---------------|
| `ITaggerProvider` | 创建 Tagger，分析文本并产出 Tag | `BookmarkGlyphTaggerProvider` |
| `IGlyphFactoryProvider` | 创建 Glyph 工厂，在边栏绘制图标 | `BookmarkGlyphFactoryProvider` |
| `IMouseProcessorProvider` | 处理编辑器边栏的鼠标事件 | `BookmarkGlyphMouseProcessorProvider` |

**MEF 组件不需要手动初始化** — VS 会自动发现并实例化标记了 `[Export]` 的类。

BookmarkStudio 中 MEF 的另一个例子 — 获取编辑器分类信息用于智能命名：

```csharp
// src/Services/BookmarkNameSuggestionService.cs
[Export(typeof(BookmarkNameSuggestionService))]
internal sealed class BookmarkNameSuggestionService
{
    [Import] private IViewClassifierAggregatorService ViewClassifierService { get; set; }
    [Import] private IClassifierAggregatorService BufferClassifierService { get; set; }

    // 获取实例需要通过 IComponentModel
    public static BookmarkNameSuggestionService? TryGetInstance()
    {
        var componentModel = Package.GetGlobalService(typeof(SComponentModel)) as IComponentModel;
        return componentModel?.GetService<BookmarkNameSuggestionService>();
    }
}
```

---

## 7. 线程模型 — UI 线程 vs 后台线程

VS 扩展开发中最容易出错的地方：

```csharp
// 切换到 UI 线程（操作 UI 元素前必须）
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

// 确认当前已在 UI 线程
ThreadHelper.ThrowIfNotOnUIThread();

// 在后台线程启动任务，结果回到 UI 线程
ThreadHelper.JoinableTaskFactory.RunAsync(async () =>
{
    // 这里可以在后台线程
    await Task.Run(() => File.ReadAllText(path));

    // 切换到 UI 线程更新界面
    await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
    label.Text = "...";
}).FireAndForget();
```

关键规则：
- **操作 DTE（文档、选择、窗口）** → 必须在 UI 线程
- **文件 I/O、JSON 解析** → 可以在后台线程（本项目中用 `Task.Run` 包裹）
- **更新 WPF 绑定** → 必须在 UI 线程

---

## 8. DTE Automation — 操作编辑器和解决方案

DTE (Development Tools Environment) 是 VS 的自动化对象模型：

```csharp
// 获取 DTE 服务
DTE2 dte = await VS.GetServiceAsync<DTE, DTE2>();

// 获取当前活动文档
Document activeDoc = dte.ActiveDocument;

// 获取文档的文本接口
TextDocument textDoc = activeDoc.Object("TextDocument") as TextDocument;

// 获取光标所在行号
int line = textDoc.Selection.ActivePoint.Line;

// 打开文件
dte.ItemOperations.OpenFile(path, EnvDTE.Constants.vsViewKindTextView);

// 跳转到指定行
textDoc.Selection.MoveToLineAndOffset(lineNumber, 1, false);

// 检查解决方案是否打开
bool isOpen = dte.Solution.IsOpen;
```

---

## 9. VSIX Manifest — 扩展的元数据

```xml
<!-- src/source.extension.vsixmanifest -->
<PackageManifest Version="2.0.0" ...>
  <Metadata>
    <Identity Id="BookmarkStudio.7ed28d42-..." Version="1.0.902" Publisher="Mads Kristensen" />
    <DisplayName>Bookmark Studio</DisplayName>
    <Description>Manage color-coded code bookmarks across your solution...</Description>
  </Metadata>
  <Installation>
    <!-- 支持的 VS 版本 -->
    <InstallationTarget Id="Microsoft.VisualStudio.Community" Version="[17.0, 18.0)">
      <ProductArchitecture>amd64</ProductArchitecture>
    </InstallationTarget>
  </Installation>
  <Assets>
    <!-- 声明包含一个 VS Package -->
    <Asset Type="Microsoft.VisualStudio.VsPackage" Path="..." />
    <!-- 声明包含 MEF 组件 -->
    <Asset Type="Microsoft.VisualStudio.MefComponent" Path="..." />
  </Assets>
</PackageManifest>
```

`source.extension.cs` 是自动生成的配套文件，提供强类型的 Vsix 信息：
```csharp
internal sealed partial class Vsix
{
    public const string Id = "BookmarkStudio.7ed28d42-...";
    public const string Name = "Bookmark Studio";
    public const string Version = "1.0.902";
}
```

---

## 10. `.csproj` — VSIX 构建配置

```xml
<!-- src/BookmarkStudio.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>      <!-- 必须是 .NET Framework -->
    <UseWPF>true</UseWPF>                          <!-- 启用 WPF -->
    <VsixDeployOnDebug>true</VsixDeployOnDebug>    <!-- F5 自动部署到实验实例 -->
    <GeneratePkgDefFile>true</GeneratePkgDefFile>  <!-- 生成包定义文件 -->
  </PropertyGroup>
</Project>
```

- `VsixDeployOnDebug=true` — 按 F5 调试时，自动将扩展安装到 VS 实验实例
- `.pkgdef` 文件 — 告诉 VS 如何加载你的扩展

---

## 11. Community.VisualStudio.Toolkit 的作用

本项目没直接用裸 VS SDK，而是用了社区封装的 Toolkit。它提供了什么便利：

| 裸 VS SDK 写法 | Toolkit 写法 |
|---------------|-------------|
| 手动实现 `AsyncPackage.InitializeAsync` 中的所有注册 | `ToolkitPackage` 基类 + Attribute 自动处理 |
| 手写 `OleMenuCommand` 创建和匹配 | `[Command(Id)]` Attribute + `BaseCommand<T>` 基类 |
| 手动管理 `ToolWindowPane` | `BaseToolWindow<T>` 基类 |
| 手动实现 `IOptionPage` | `BaseOptionModel<T>` + `BaseOptionPage<T>` |
| 手动调用 `GetServiceAsync` 每个服务 | `VS.GetServiceAsync<T>` 扩展方法 |
| 手写事件订阅/取消订阅 | `VS.Events.SolutionEvents.OnAfterOpenSolution` |

---

## 总结

整个 VS 扩展的运行流程：

```
VS 启动
  → 加载 .vsixmanifest，发现 Package
  → 匹配 AutoLoad 条件时调用 Package.InitializeAsync()
  → Package 注册命令、工具窗口、选项页、事件监听
  → 用户操作触发命令 → Command.ExecuteAsync()
  → 命令调用 Service 层 → 操作数据 → 更新 UI
  → UI 通过 WPF 绑定自动刷新（ViewModel → XAML）
```

理解了这个流程，就理解了整个项目的工作方式。

<p align="center">
  <img src="Resources/icon-preview.png" width="128" height="128" alt="Tusi icon">
</p>

<h1 align="center">Tusi 兔斯</h1>
<p align="center">macOS 菜单栏翻译工具，只做一件事，但做到随手即走。</p>

## 能做的事

- **自动识别语言，不用选方向**：输入**中文** → 翻译成英文；输入**任何其他语言** → 翻译成中文。方向靠字符脚本本地判定（不依赖网络、不依赖模型），中英夹杂的技术句子也能判对。
- **Menubar 常驻，随用随走**：`⌥ Space` 呼出，翻完复制，面板自己收起，不占 Dock、不留窗口。
- **BYOK**：自己填接口地址 + API Key + 模型名，兼容任何 OpenAI-compatible 网关（DeepSeek、OpenRouter、SiliconFlow、Groq、本地 Ollama……）。没有预置的供应商列表，你的网关你做主。
- **主用 + 备用，自动切换**：配置两套 BYOK，主用请求失败时自动重试备用，不用手动切换。
- **三种文风**：口语 / 标准 / 正式，随时切换，切完自动重新翻译当前内容。
- **可选自动复制**：翻译完成直接进剪贴板，不用再点一次。
- **智能引号**：直引号 `"` `'` 自动转成排版引号 `“ ” ‘ ’`，代码片段和代码块里的引号保持原样不受影响。
- **快捷键可自定义**：复制快捷键（默认 `⇧⌘C`）可自行录制。

## 主要使用场景

1. **不用再打开一个 AI 网页/客户端，然后打一句「翻译成英文」**——选中文字，`⌥ Space`，粘贴进去，回车，复制，粘回去。全程不切出当前工作流。
2. **写一封稍微正式一点的英文邮件**：中文起草，Tusi 译成英文，切到「正式」文风精修语气，一句话搞定不用自己抠措辞。
3. 日常阅读英文/日文/其他语言的只言片语，不需要完整打开翻译网站的场合。

## 使用

| 操作 | 快捷键 |
|---|---|
| 呼出 / 收起面板 | `⌥ Space`（或点菜单栏图标） |
| 翻译 | `⏎`（大键盘和小键盘回车都可以） |
| 输入换行 | `⇧⏎` / `⌘⏎` |
| 复制译文 | 可自定义（默认 `⇧⌘C`），或点复制按钮 |
| 打开设置 | `⌘,` |
| 关闭面板 / 返回 | `Esc` |

面板右下角图钉可固定面板（点击外部不自动关闭）。重新打开面板时，若上一次翻译已完成，输入框内容会自动全选，方便直接输入新内容覆盖。

## BYOK 配置

设置页有**两套**可自填的配置（主用 / 备用），每套四项：

- **接口地址**：如 `https://api.deepseek.com`、`https://openrouter.ai/api/v1`
- **模型**：如 `deepseek-chat`、`deepseek/deepseek-v4-flash`
- **API Key**
- **供应商路由（可选）**：仅 OpenRouter 等支持 `provider` 参数的网关生效，如 `novita`，多个用逗号分隔

点标签页在两套之间切换，"设为主用"决定谁先跑。开启**"主用失败时自动切换到备用"**后，主用请求出错（且尚未吐出任何字符）会自动改用备用重试；切换发生时底部弹一个瞬时提示，看完即走。备用没填满时会自动跳过，不会拖累能用的主用。

API Key 只保存在本机钥匙串（单个条目，两套 key 一起存取，避免每次启动弹两次授权），设置页每套都有"测试连接"可单独验证。

## 安装

前往 [Releases](../../releases) 下载：

- **Tusi-arm64.zip** — Apple Silicon（M1 及以上）专用，体积更小
- **Tusi-universal.zip** — 同时支持 Apple Silicon 和 Intel

解压后把 `Tusi.app` 拖进「应用程序」即可。首次打开如果被 Gatekeeper 拦截（因为不是从 App Store 或付费开发者账号签发），右键点「打开」确认一次即可，之后正常双击启动。

## 从源码构建

```bash
git clone <本仓库地址>
cd Tusi
./build.sh          # 生成 build/Tusi.app
./build.sh --open   # 构建并启动
```

纯 Swift + SwiftUI + AppKit，零第三方依赖，要求 macOS 14+。默认按当前架构构建；发布时使用 `arch -arch <arm64|x86_64> swift build -c release` 分别产出后用 `lipo` 合并成 universal 二进制。

`build.sh` 会自动探测本机是否有可用的代码签名身份：找到就用它签名（授权能跨重新编译保留，不会每次启动都要求钥匙串密码），找不到就退回 ad-hoc（行为与之前一致，不影响任何人直接构建）。

## 调试

`TUSI_PREVIEW=main|empty|settings` （可加 `TUSI_DARK=1`）启动会固定面板并填充示例内容，方便截图检查 UI。预览模式使用独立的临时配置域，**不会触碰真实的钥匙串和设置**。`TUSI_SLOWMO=1` 会把面板动画放慢十倍，便于检查过渡效果。

## 结构

```
Sources/Tusi/
├── TusiMain.swift          # 入口（accessory 应用，无 Dock 图标）
├── AppDelegate.swift       # 菜单栏图标、主菜单、右键菜单、调试预览入口
├── PanelController.swift   # 无边框浮动面板：定位、高度动画、键盘事件、快捷键录制
├── HotkeyManager.swift     # ⌥Space 全局热键（Carbon，无需辅助功能权限）
├── Core/
│   ├── TranslationEngine.swift   # 状态机：输入 → 方向判定 → 流式翻译 → 复制
│   ├── TranslationService.swift  # OpenAI-compatible SSE 流式客户端
│   ├── LanguageDetector.swift    # 基于字符脚本的方向判定 + 三档文风定义
│   ├── SmartQuotes.swift         # 直引号 → 排版引号，跳过代码片段/代码块
│   ├── SettingsStore.swift       # UserDefaults + 两套 BYOK profile + fallback 链
│   ├── Keychain.swift            # API Key 合并存取（单条目，两把 key 一起读写）
│   ├── KeyCombo.swift            # 可录制的自定义快捷键
│   └── PanelState.swift
└── UI/
    ├── RootView.swift        # 页面切换容器（圆角/毛玻璃/描边已移交 AppKit 绘制）
    ├── TranslatorView.swift  # 主界面：自适应输入区、流式结果、底栏
    ├── SettingsView.swift    # 设置：BYOK 字段、供应商路由、快捷键录制、测试连接
    ├── Components.swift      # 面板容器（PanelContainerView）、方向胶囊、复制按钮、文风选择器等
    └── Theme.swift           # 系统强调色与常量
```

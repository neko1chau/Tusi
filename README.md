<img src="Resources/icon-preview.png" width="88" height="88" align="left" alt="">

# Tusi

macOS 菜单栏上的翻译工具。给它中文，返回英文；给它别的语言，返回中文。方向自动判断，不用手动选。

<br clear="left">

## 它做什么

按 `⌥ Space` 呼出一个小面板，输入或粘贴文字，回车翻译，复制走人，面板自己收起。语言方向由本地判断（按字符判定，不联网、不问模型），所以中英夹杂的句子也能判对该往哪个方向翻。

翻译走你自己的 API。设置里填接口地址、API Key、模型名，任何 OpenAI 兼容的服务都行——DeepSeek、OpenRouter、SiliconFlow、本地 Ollama 等等。可以配两套，主用挂了自动换备用。

其它一些小功能：三种文风（口语 / 标准 / 正式）随时切换；翻完可选自动复制到剪贴板；输出的直引号会规整成中英文排版引号，代码片段除外。

几个我自己常用的场景：想翻一句话时不用再开一个 AI 网页、打一遍「翻译成英文」；写英文邮件时用中文起草再翻过去，切到「正式」润一下语气；读到几句外文顺手扔进去看看意思。

## 安装

在 [Releases](../../releases) 下载：

- `Tusi-arm64.zip` — Apple Silicon（M1 及以后）
- `Tusi-universal.zip` — 同时支持 Apple Silicon 和 Intel

解压，把 `Tusi.app` 拖进「应用程序」。首次打开若被 Gatekeeper 拦（因为没走 Apple 公证），右键点「打开」确认一次就行。需要 macOS 14 或更新版本。

## 快捷键

| | |
|---|---|
| 呼出 / 收起面板 | `⌥ Space`，或点菜单栏图标 |
| 翻译 | `⏎` |
| 输入里换行 | `⇧⏎` 或 `⌘⏎` |
| 复制译文 | `⇧⌘C`（可改），或点复制按钮 |
| 打开设置 | `⌘,` |
| 返回 / 关闭 | `Esc` |

面板右下角有个图钉，钉住后点面板外面不会自动关。上一次翻译完成后再次打开面板，输入框内容会自动全选，直接打字就能覆盖。

## 配置 API

设置页里有两套配置，主用和备用，每套四项：

- 接口地址，比如 `https://api.deepseek.com` 或 `https://openrouter.ai/api/v1`
- 模型名，比如 `deepseek-chat`
- API Key
- 供应商路由（可选），只对 OpenRouter 这类支持 `provider` 参数的网关有用，填 `novita` 之类，多个用逗号隔开

「设为主用」决定先用哪套。开了「主用失败时自动切换到备用」以后，主用请求出错（且还没吐出任何字）会自动改用备用重试。备用没填完整会自动跳过。

API Key 存在本机钥匙串里，不进配置文件，也不上传。每套配置都有「测试连接」可以单独验一下。

## 从源码构建

```
./build.sh          # 生成 build/Tusi.app
./build.sh --open   # 构建并打开
```

纯 Swift + SwiftUI + AppKit，没有第三方依赖。默认按当前机器的架构构建，`TUSI_ARCH=universal ./build.sh` 可以产出 arm64 + Intel 的通用二进制。

`build.sh` 会看本机有没有可用的代码签名证书：有就用它签，这样授权能跨重新编译保留，不会每次启动都问钥匙串密码；没有就退回 ad-hoc 签名，照样能用。

## 代码结构

```
Sources/Tusi/
├── TusiMain.swift          入口，menubar-only 应用，无 Dock 图标
├── AppDelegate.swift       菜单栏图标、菜单、调试预览入口
├── PanelController.swift   浮动面板：定位、高度动画、键盘、快捷键录制
├── HotkeyManager.swift     ⌥Space 全局热键
├── Core/
│   ├── TranslationEngine.swift    输入 → 判方向 → 流式翻译 → 复制
│   ├── TranslationService.swift   OpenAI 兼容的 SSE 流式请求
│   ├── LanguageDetector.swift     按字符脚本判方向，三档文风
│   ├── SmartQuotes.swift          直引号转排版引号，跳过代码
│   ├── SettingsStore.swift        设置、两套配置、fallback 链
│   ├── Keychain.swift             API Key 存取
│   ├── KeyCombo.swift             可录制的快捷键
│   └── PanelState.swift
└── UI/
    ├── RootView.swift        页面容器
    ├── TranslatorView.swift  翻译主界面
    ├── SettingsView.swift    设置界面
    ├── Components.swift      面板容器、方向胶囊、复制按钮、文风选择器
    └── Theme.swift
```

调试时 `TUSI_PREVIEW=main|empty|settings`（可加 `TUSI_DARK=1`）会固定面板并填示例内容，用独立的临时配置，不碰真实钥匙串和设置。`TUSI_SLOWMO=1` 把动画放慢十倍。

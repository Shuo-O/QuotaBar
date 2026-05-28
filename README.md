# QuotaBar

**中文** | [English](README.en.md)

macOS 状态栏工具，实时显示 Claude Code 和 Codex 的用量与重置倒计时。

---

## 功能

- **两种显示模式**，菜单随时切换：
  - **文字模式**：状态栏显示 `C 53%  X 84%`，颜色直接反映紧张程度
  - **图标环模式**：品牌图标本身被一分为二——亮色扇形 = 剩余量，暗色扇形 = 已用量
- 文字模式可切换显示**使用量**或**剩余量**
- 菜单显示精确百分比 + **重置倒计时**（如"还剩 1h52m"）
- 可单独显示或隐藏 Claude / Codex
- **数据来源直接、准确**：
  - Claude：调用 `claude.ai/api/oauth/usage`（复用 Claude Code 的 OAuth 凭证，和 `/usage` 命令数据一致）
  - Codex：读取最新 session JSONL 中的 `rate_limits` 字段（来自 ChatGPT 后端响应）
- 支持手动配置数据目录和 token 上限

## 颜色规则

| 用量（文字/图标环） | 颜色 |
|---|---|
| < 50% | 🟢 绿色 |
| 50 – 79% | 🟡 黄色 |
| 80 – 94% | 🟠 橙色 |
| ≥ 95% | 🔴 红色 |
| 无数据 | ⚫ 灰色 |

> 图标环模式：亮色弧线 = 剩余量（绿色表示充裕，红色表示快空），暗色区域 = 已用

## 截图

<p align="center">
  <img src="screenshots/menubar_text.png" alt="文字模式" width="240"/>
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/menubar_ring.png" alt="图标环模式" width="160"/>
  <br><em>文字模式 &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 图标环模式</em>
</p>

<p align="center">
  <img src="screenshots/menu_open.png" alt="菜单展开" width="240"/>
  <br><em>菜单：精确百分比 + 重置倒计时</em>
</p>

## 安装

### 从源码构建（需要 Xcode Command Line Tools）

```bash
git clone https://github.com/Shuo-O/QuotaBar.git
cd QuotaBar
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
open build/QuotaBar.app
```

### 开发运行

```bash
Scripts/package_app.sh && open build/QuotaBar.app
```

> `swift run` 不可用：macOS 只向通过 Launch Services 启动的 `.app` bundle 授予 WindowServer GUI session，裸二进制无法显示菜单栏图标。

## 配置

点击菜单栏图标 → **配置数据源…**

| 设置项 | 说明 | 默认值 |
|---|---|---|
| Claude 项目路径 | Claude Code 项目文件目录 | `~/.claude/projects` |
| Codex 会话路径 | Codex session 文件目录 | `~/.codex/sessions` |
| Claude Token 上限 | 5小时窗口 token 预算（离线回退时使用） | 100,000 |

> 路径支持填写父目录，会自动向下递归查找 `.jsonl` 文件。

## 数据来源说明

| 服务 | 主要来源 | 回退方案 |
|---|---|---|
| Claude | `claude.ai/api/oauth/usage`（OAuth，无需额外配置） | 扫描 `~/.claude/projects/**/*.jsonl` 计算 5h token 用量 |
| Codex | `~/.codex/sessions/**/*.jsonl` 中的 `rate_limits` 字段 | — |

Claude 数据首次读取时 macOS 会弹出钥匙链授权对话框，允许一次即可。

## 系统要求

- macOS 14 (Sonoma) 或更新版本
- 已安装并登录 [Claude Code](https://claude.ai/code) 和/或 [Codex CLI](https://github.com/openai/codex)

## 图标来源

- Claude：Simple Icons Claude SVG（MIT License）
- Codex：OpenAI 2025 symbol SVG from Wikimedia Commons

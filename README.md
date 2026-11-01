# context-bar — Claude Code 面板里的实时 context 读数

一个 **Claude Code mod**（engine function hooks），在 VS Code 面板的对话框上方显示：

```
ctx ██████░░░░ 62% · 124k/200k
```

不修改扩展本体的 `webview/index.js`，所以扩展升级不会把它冲掉。数据来自引擎自己的 `$.session.usage()`，不是 transcript——代理/别名环境下也正确。

## 兼容性

- 测试于 **Claude Code 2.1.314**（VS Code extension, Windows）。
- 需要支持 mod（`dev-mods` / `CLAUDE_CODE_PLUGIN_DIRS`）的 engine。
- 纯 terminal / `-p` 会话不绘制，避免和 `~/.claude/statusline.sh` 重复。

## 安装

mod 必须放在 `dev-mods` 布局下，而不是当作 marketplace plugin：

```
~/.claude/dev-mods/<uuid>/context-bar/
  .claude-plugin/plugin.json
  hooks/hooks.json
  hooks/register.ts
```

然后把 mod 文件夹写进 `~/.claude/settings.json` 的 `env`：

```json
{
  "env": {
    "CLAUDE_CODE_PLUGIN_DIRS": "C:\\Users\\<you>\\.claude\\dev-mods\\<uuid>\\context-bar"
  }
}
```

> extension 自己启动的 engine 不会收到 `--plugin-dir`，所以需要这个 env key 才能扫到 dev-mod。
> 2.1.220 的终端 CLI 会忽略这个 key，不会报错；2.1.314 的 engine 会加载并 `admitted`。

### Windows（PowerShell）

```powershell
git clone git@github.com:GZY-SUPER-HACKER/claude-code-context-bar-mod.git
cd claude-code-context-bar-mod
.\install.ps1            # 复制到 dev-mods，并打印 settings 里要加的键
# 或：.\install.ps1 -WriteSettings   # 自动合并进 settings.json（先备份）
```

之后在 VS Code 执行 **Developer: Reload Window**。

### Linux / macOS

```bash
git clone git@github.com:GZY-SUPER-HACKER/claude-code-context-bar-mod.git
cd claude-code-context-bar-mod
./install.sh             # 复制到 dev-mods，并打印 settings 里要加的键
# 或：./install.sh --write-settings
```

然后 reload VS Code 窗口。

## 为什么用 `$.ui.status` 而不是 `AbovePrompt`

2.1.314 的引擎里 `RENDER_SURFACES_OF` 是：

```text
AbovePrompt: ["terminal", "desktop"], Pane: <all>
```

所以 `ui.render` 的 `AbovePrompt` **不会在 `vscode` surface 触发**。VS Code webview 会把 `$.ui.status` 的行画在 composer 上方的同一个容器里（`data-engine-status`），因此视觉位置就是「对话框上方」。这是 2.1.314 上不改 bundle 时最接近的受支持位置。

- `Pane` 在所有 surface 都会触发，但 webview ≥800px 时会 dock，不适合做常驻 bar。
- 如果未来 engine 放开 `AbovePrompt` 到 `vscode`，把 `register.ts` 里的 `$.ui.status(text)` 换成 `ui.render` on `{ component: 'AbovePrompt' }` 即可。

## 行为细节

- 每 1.5s 刷新一次，并在 `session.start` / `turn.complete` / `session.attach` 时立即刷新。
- `session.end` 时取消 timer（`$.clock.every` 返回 `Timer`，必须 `stop?.cancel()`）。
- fresh / just-compacted session 显示 `—`，不会伪造 `0%`。
- 只在有非 terminal surface 时绘制。

## 配置

编辑 `hooks/register.ts` 顶部：

```ts
const BAR_CELLS = 10   // bar 格子数
const TICK_MS = 1500   // 刷新间隔（ms）
```

## 验证

```bash
claude plugin validate <mod folder>
```

真实加载测试（用 2.1.314 的 engine）：

```bash
claude --plugin-dir <mod folder> -p "Reply with exactly: OK" --debug-file /tmp/mod.log
grep -E "hooks module context-bar|admitted|Hook load failed|TypeError" /tmp/mod.log
```

期望看到：

```text
hooks module context-bar@inline loaded ... events: session.start,turn.complete,session.attach,session.end
plugin.register: context-bar ... admitted
```

## 回滚

1. 从 `settings.json` 的 `env` 删除 `CLAUDE_CODE_PLUGIN_DIRS`（或恢复安装时的 `.bak-context-bar-*`）。
2. 删除 `~/.claude/dev-mods/<uuid>`。
3. `Developer: Reload Window`。

## 文件

```
.claude-plugin/plugin.json   manifest
hooks/hooks.json             { "modules": ["./register.ts"] }
hooks/register.ts            session.start / turn.complete / session.attach / session.end
install.ps1                  Windows 安装脚本
install.sh                   Linux/macOS 安装脚本
```

## 注意

- 这个 repo 只包含 mod 代码，不包含 `settings.json`、token 或任何机器凭据。
- 安装脚本会备份 `settings.json`，但自动写入只在显式 `-WriteSettings` / `--write-settings` 时发生。
- 远端 5880 的旧副本用的是 marketplace 路线且有 `stop?.()` bug；请以本 repo 为准。

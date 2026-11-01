# JUNCTION 说明 — ssh-transfer

> 本目录已与四个全局 skill 目录建立 junction，**实时双向同步，改哪边都一样**。

## 指向关系

| 项 | 路径 |
|----|------|
| 全局路径（junction，Claude Code） | `C:\Users\Administrator\.claude\skills\ssh-transfer` |
| 全局路径（junction，DeepSeek Harness） | `C:\Users\Administrator\.dsh\skills\ssh-transfer` |
| 全局路径（junction，Codex） | `C:\Users\Administrator\.codex\skills\ssh-transfer` |
| 全局路径（junction，ZCode） | `C:\Users\Administrator\.zcode\skills\ssh-transfer` |
| 全局路径（junction，Qoder CN） | `C:\Users\Administrator\.qoder-cn\skills\ssh-transfer` |
| 实际目录（F 仓库） | `F:\idea-workspase-skills\ssh-transfer` |

## 说明

- 全局四个目录都是指向 F 仓库的 junction，四处是**同一个目录**，不是副本。
- 修改 F 仓库，全局立刻生效；在全局路径下改文件，F 仓库同步变化。
- 日常维护只改 F 仓库（git 提交推送后全局自动一致），**不需要手动复制同步**。

## PATH 垫片（与目录 junction 无关的另一套机制）

`.local\bin\fsend.cmd` 是**符号链接**，指回本仓 `scripts\fsend.cmd`：`.local\bin` 在 C: 盘、本仓在 F: 盘，跨卷做不了硬链接，只能用符号链接，这样改仓内脚本 PATH 立即生效。

体检/重建走 `agent-config-sync-check\scripts\install-shims.ps1`（一条命令管三个垫片，垫片表登记在 `sync-config.json` 的 `pathShims`，不带 `-Apply` 只体检）。`sync-check.ps1` 第 14 项检查一起看管垫片，`-Fix` 时由它调用同一个安装脚本；上面的目录 junction 仍按本页方式管。

## 检查是否正常

```bash
cmd /c dir "C:\Users\Administrator\.claude\skills" | findstr ssh-transfer
cmd /c dir "C:\Users\Administrator\.dsh\skills"    | findstr ssh-transfer
cmd /c dir "C:\Users\Administrator\.codex\skills"  | findstr ssh-transfer
cmd /c dir "C:\Users\Administrator\.zcode\skills"  | findstr ssh-transfer
cmd /c dir "C:\Users\Administrator\.qoder-cn\skills" | findstr ssh-transfer
```

正常应显示 `<JUNCTION>  ...  ssh-transfer`。

## 回滚方法（恢复成独立副本）

```bat
rd "C:\Users\Administrator\.claude\skills\ssh-transfer"
rd "C:\Users\Administrator\.dsh\skills\ssh-transfer"
rd "C:\Users\Administrator\.codex\skills\ssh-transfer"
rd "C:\Users\Administrator\.zcode\skills\ssh-transfer"
rd "C:\Users\Administrator\.qoder-cn\skills\ssh-transfer"
```

> 注意：`rd` 不要加 `/s`，否则可能递归进 F 源目录。删除 junction 只删链接，不删 F 源目录。

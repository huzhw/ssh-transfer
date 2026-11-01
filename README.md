# ssh-transfer — 传文件走命令行，别走模型上下文

**定位**：给 AI 助手（Claude Code / DSH / Codex / ZCode / Qoder CN）用的"往服务器传文件"标准做法。文件字节走 SSH 数据通道，模型只收一行结果，几百 KB 和几个 GB 一样安静。

## 相关技能

- [agent-config-sync-check](https://github.com/huzhw/agent-config-sync-check)：八端同步守卫：链接/硬链接/README 同步检查与修复
- [git-commit](https://github.com/huzhw/git-commit-skill)：Git 提交规范
- [daily-record-gitlab-md](https://github.com/huzhw/daily-record-gitlab-md-skill)：日报记录（第一步）
- [daily-merge-gitlab-excel](https://github.com/huzhw/daily-merge-gitlab-excel-skill)：日报合并（手动兜底，已由日报管家接管，不推荐）
- [code-check](https://github.com/huzhw/code-check-skill)：增量代码隐患检查
- [deepseek-harness-settings-curator](https://github.com/huzhw/deepseek-harness-settings-curator)：DeepSeek Harness 模型配置梳理
- [deepseek-harness-plugin-doctor](https://github.com/huzhw/deepseek-harness-plugin-doctor)：DeepSeek Harness 插件与升级体检医生
- [dev-env-upgrade](https://github.com/huzhw/dev-env-upgrade)：开发环境升级医生：版本体检/最新版查询/安全升级
- [reread-rules](https://github.com/huzhw/reread-rules-skill)：重载 CLAUDE.md / AGENTS.md 规则
- [coding-rules](https://github.com/huzhw/coding-rules)：编码规则库（独立仓库，非 skill）
- [daily-report-panel](https://github.com/huzhw/daily-report-panel)：日报管家（关联仓库，非 skill，自动合并/导出/发件）
- [memory-ai-cleanup](https://github.com/huzhw/memory-ai-cleanup)：memory-ai 记录定期清理：删过期流水、摘索引死链、清 tmp 残留
- [prd](https://github.com/huzhw/prd-skill)：PRD 生成器（一句话需求→结构化需求文档）
- [ralph](https://github.com/huzhw/ralph-skill)：PRD 转 prd.json（Ralph 自主执行格式）

## 解决了什么问题

MCP 工具 `ssh__sftp-upload` 的入参是**文件内容本身**——几十 KB 的文件就够把上下文冲爆，回显还是一屏"文件大小"明细。`ssh-mcp` 本有零 token 的 `sftp-upload-file`，但它在 Windows 上被代码直接拒绝（`local-path.js` 里 `platform() === 'win32'` 就报错，原因是 transferRoot 的私有权限在 Windows 上验证不了）。

于是只剩两条路：**要么内容进上下文，要么绕开 MCP 走命令行**。本技能是后者，一个 `scp` 调用搞定。

## 使用

```powershell
# 上传
fsend "F:\build\app.war" root@10.0.0.9:/opt/tomcat/webapps/

# 下载
fsend -Down root@10.0.0.9:/var/log/app.log "N:\文件下载\ai自动下载\"

# 多文件
fsend "F:\a.jar" "F:\b.properties" root@10.0.0.9:/opt/app/lib/

# 额外做 md5 双端比对（默认只比字节数）
fsend -Verify "F:\build\big.iso" root@10.0.0.9:/data/
```

不装垫片时的等价原生命令：

```powershell
scp -q -o BatchMode=yes "F:\build\app.war" root@10.0.0.9:/opt/tomcat/webapps/
ssh -o BatchMode=yes root@10.0.0.9 "ls -l /opt/tomcat/webapps/app.war"
```

退出码：`0` 成功、`1` 传输或校验失败、`2` 参数错。

## 文件结构

```
ssh-transfer\
├── SKILL.md                  技能说明（Agent 读）
├── README.md                 本文件（GitHub 读者版）
├── JUNCTION说明.md           各端链接关系与回滚方式
├── .gitignore
└── scripts\
    ├── fsend.ps1             真身：参数解析 + scp 调用 + 字节数/md5 校验
    └── fsend.cmd             垫片源（绝对路径转发 fsend.ps1）
```

## 安装

```powershell
git clone https://github.com/huzhw/ssh-transfer.git ~/.claude/skills/ssh-transfer
```

PATH 垫片（跨卷只能用符号链接，硬链接会报"系统无法将文件移到不同的磁盘驱动器"）：

```bat
cmd /c "mklink C:\Users\Administrator\.local\bin\fsend.cmd F:\idea-workspase-skills\ssh-transfer\scripts\fsend.cmd"
```

三个垫片（`fsend` / `mvninfo` / `envcheck`）可一条命令体检或重建，脚本在 dev-env-upgrade 仓：

```powershell
# 体检：链接是否都指回仓内真身（有问题退出码 1）
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\idea-workspase-skills\agent-config-sync-check\scripts\install-shims.ps1"

# 重建/修复（幂等，旧拷贝先备份成 .bak-<时间戳>）
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\idea-workspase-skills\agent-config-sync-check\scripts\install-shims.ps1" -Apply
```

## 许可

MIT

最后修改：2026-11-01

---
name: ssh-transfer
description: 服务器传文件的命令行做法：用 scp/sftp 流式传输，文件内容不进模型上下文、回显只有几行。Windows 上走 fsend 垫片（PATH 可直接敲）；ssh-mcp 的 sftp-upload/sftp-download 会把文件内容当参数塞进上下文，大文件必爆，只在传短文本时用。触发词：传文件、上传文件、下载文件、发文件到服务器、sftp、scp、rsync、传大文件、把文件给服务器、ssh 传文件、文件太小/太大、sftp-upload、fsend。
---

# ssh-transfer —— 传文件走命令行，别走模型上下文

## 这是什么

往服务器传文件（或从服务器拉文件）的固定做法：**一次 `scp` 调用，文件字节走 SSH 通道，模型只收几行结果**。

对照表（同一件事，两条路的代价差几个数量级）：

| 做法 | 文件字节走哪 | 回显 | 适用 |
|---|---|---|---|
| ✅ `scp` / `sftp` / `fsend` | SSH 数据通道 | 2~3 行（路径 + 字节数） | 任意大小，二进制、压缩包、jar、日志 |
| ❌ `ssh__sftp-upload` | **模型上下文**（内容当参数传） | 整份内容 + 尺寸明细 | 仅几百字节的短文本 |
| ❌ 写 base64 再塞命令 | 模型上下文 | 更长 | 不要用 |

**为什么不能在 Windows 上用 ssh-mcp 的流式工具**：`ssh-mcp` 的 `sftp-upload-file` / `sftp-download-file` 本可零 token，但它在 Windows 上直接拒绝 —— `build/tools/local-path.js` 里 `platform() === 'win32'` 就报 "Streaming SFTP file tools are not available on Windows"，因为 transferRoot 的私有权限在 Windows 上无法验证。于是模型只能退到 `sftp-upload`，那条路就是把文件内容当参数。**结论：Windows 端一律走命令行。**

## 快速上手

```powershell
# 上传（本地文件 → 远端目录）
fsend "F:\build\app.war" root@192.168.80.139:/opt/tomcat/webapps/

# 下载（远端文件 → 本地目录）
fsend -Down root@192.168.80.139:/var/log/app.log "N:\文件下载\ai自动下载\"

# 多个文件一次传
fsend "F:\a.jar" "F:\b.properties" root@192.168.80.139:/opt/app/lib/

# 强制 md5 双端比对（默认只比字节数）
fsend -Verify "F:\build\big.iso" root@192.168.80.139:/data/
```

不装垫片也能直接用原生命令，效果一样：

```powershell
scp -q -o BatchMode=yes "F:\build\app.war" root@192.168.80.139:/opt/tomcat/webapps/
ssh -o BatchMode=yes root@192.168.80.139 "ls -l /opt/tomcat/webapps/app.war"
```

## 用法与约定

- **`fsend` 垫片**：`C:\Users\Administrator\.local\bin\fsend.cmd` → 符号链接指向本仓 `scripts\fsend.cmd` → 转发 `scripts\fsend.ps1`。改了仓内脚本，PATH 入口立即跟着变（跨卷做不了硬链接，只能用符号链接）。
- **`BatchMode=yes` 是硬性要求**：认证失败立刻报错退出，绝不停在密码提示上等输入（模型会话卡死的主因）。
- **`-q`**：关掉 scp 的进度条，回显只剩结果行。
- **默认校验字节数，`-Verify` 才比 md5**：SSH 本身保证传输完整性，md5 是额外保险；GB 级文件算 md5 会撞命令超时，所以不做默认。
- **远端路径以 `/` 结尾 = 目录**，否则当文件名。
- **保底手段**：`scp` 不通时先 `ssh -o BatchMode=yes <host> echo ok` 分离"网络/认证"还是"路径"问题；`ssh` 也失败就是 key 授权或网络本身的事，跟传输无关。

## 垫片安装（换机器时照做）

```bat
rem 仓内已有的三个垫片，装到 PATH 目录（跨卷只能符号链接，不能硬链接）
cmd /c "mklink C:\Users\Administrator\.local\bin\fsend.cmd    F:\idea-workspase-skills\ssh-transfer\scripts\fsend.cmd"
cmd /c "mklink C:\Users\Administrator\.local\bin\mvninfo.cmd   F:\idea-workspase-skills\dev-env-upgrade\scripts\mvninfo.cmd"
cmd /c "mklink C:\Users\Administrator\.local\bin\envcheck.cmd  F:\idea-workspase-skills\dev-env-upgrade\scripts\envcheck.cmd"
```

`mklink` 建符号链接需要管理员权限（或开启开发者模式）。

## 坑清单

1. **跨卷做不了硬链接**：`mklink /H` 在 C: → F: 会报"系统无法将文件移到不同的磁盘驱动器"，PATH 垫片只能符号链接或拷贝。
2. **`%~dp0` 在符号链接下指向链接所在目录**，所以垫片里写脚本路径用**绝对路径**，不要用 `%~dp0`，否则换个位置就找不到真身。
3. **PowerShell 脚本纯 ASCII**：PS 5.1 把无 BOM 文件按 ANSI 解析，脚本里写中文会劈坏语法；中文文案放 JSON 配置或调用方输出。
4. **多文件时 scp 最后一个是目标**：本地路径里含空格必须加引号，否则会被当多个文件。
5. **`sftp -b -` 可做无交互批处理**（`printf 'put x\nls\n' | sftp -b - host`），但 `fsend` 已覆盖常规场景，不必绕。
6. **别用 rsync**：本机没装 rsync 客户端（`where rsync` 查无），139 那类机器上有但本地没有，别写依赖它的命令。

## 文件结构

```
ssh-transfer\
├── SKILL.md                  本文件
├── README.md                 GitHub 读者版说明
├── JUNCTION说明.md           各端链接关系与回滚方式
├── .gitignore
└── scripts\
    ├── fsend.ps1             真身：参数解析 + scp 调用 + 校验
    └── fsend.cmd             垫片源（绝对路径转发 fsend.ps1）
```

最后修改：2026-11-01

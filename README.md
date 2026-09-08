# DSH 手机远程控制 · 完整设置指南（Mac + iPhone，从零到满血实时）

> 本指南基于**实测跑通**的方案整理。目标：手机（iPhone）通过 SSH 隧道实时控制 Mac 上运行的 DeepSeek Harness（dsh web）。
> 全程只需：一台一直开机的电脑 + 一部手机 + 一个 Tailscale 账号。标注「必做」的不要跳过。
> **本文以「Mac + iPhone」为主；安卓手机 / Windows 电脑的差异见文末「附录：Windows 电脑 + 安卓手机（变体）」**，核心机制不变。

---

## 0. 前置确认（开始前先回答）

**问：下载 Tailscale / Termius 需要 VPN 和美区 Apple ID 吗？**

- **一般不需要。**
  - **Mac 端**：Tailscale 直接去官网 `https://tailscale.com/download/mac` 下载，或 `brew install --cask tailscale`，跟地区无关。
  - **iPhone 端**：Tailscale、Termius 都在 App Store（全球）有，香港/台湾/新加坡/北美等账号都能搜到。
- **特殊情况（中国大陆）**：App Store 里 **Tailscale 可能不在架**（它属于 VPN/代理类，大陆区下架）。这时需要：
  - 一个**非大陆地区的 Apple ID**（登录 App Store 下载）；或
  - 先有 VPN 连上，再从官网/TestFlight 装。
- **结论**：若你的 App Store 能搜到 Tailscale 和 Termius，**跳过本步**；搜不到，就先解决 Apple ID / VPN 再继续。**这一步搞定前，别开始。**

**其他前提**
- 一台能一直开机的 **Mac**（这是跑 dsh web 的主机）。
- **iPhone**，与 Mac 登录**同一个 Tailscale 账号**。
- DSH 在本机已装好、配有 DeepSeek API 凭据（能正常 `pnpm dsh web`）。
- Node ≥ 22、pnpm 已装。

---

## 1. 装 Tailscale（Mac + iPhone）

**Mac：**
```bash
brew install --cask tailscale
```
打开 Tailscale 应用 → 登录 → 确认状态是 **Connected**（连上）。
**开 MagicDNS**：Tailscale 设置里 Open MagicDNS（或用 CLI：`tailscale up --accept-dns=true`）。

**iPhone：**
App Store 装「Tailscale」→ 登录 **同一个账号** → 打开连接 → 设置里开 **MagicDNS**。

**验证（Mac 终端）：**
```bash
tailscale status
```
应能看到 iPhone 和 Mac 两台，Mac 那台的 `100.x.x.x` 就是**它的 tailnet IP**，记下来。

---

## 2. 启动 dsh web（Mac，记得带 --trusted-host）

进到 dsh 源码目录，启动（**必须带 `--trusted-host <你的 tailnet 域名>`**，否则手机访问会被 403/401 拦）：
```bash
cd ~/deepseek-harness          # 你的 dsh 目录
pnpm dsh web --trusted-host <你的Mac>.ts.net
```
> `<你的Mac>.ts.net` 用 Tailscale 给你的 MagicDNS 主机名，形如 `ccmacbook-pro-1.tailxxxx.ts.net`。查法：
> ```bash
> tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'
> ```

启动后会打印 token 网址，**记下来**（每进程唯一）：
```
dsh web: http://127.0.0.1:3080/?token=<TOKEN>
```

> **推荐**：用脚本启动，自动打印手机可用的两套网址（Tailscale + SSH），重启换 token 也不用自己拼：
> 把下面的片段存成 `~/dsh-phone-url.sh` 并 `chmod +x`，以后用它启动 dsh web 即可。
> ```bash
> #!/bin/zsh
> HOST="<你的Mac>.ts.net"; DIR="$HOME/deepseek-harness"
> (cd "$DIR" && pnpm dsh web --trusted-host "$HOST") 2>&1 | while IFS= read -r l; do
>   [[ "$l" =~ "http://127.0.0.1:3080/?token=" ]] && { t="${l##*token=}"; t="${t%% *}"; echo "📱 SSH:    http://127.0.0.1:3080/?token=$t"; echo "📱 Tailscale: https://$HOST/?token=$t"; }
>   echo "$l"
> done
> ```

---

## 3. 多准备一条：给手机开 SSH 免密（为了「满血实时」）

> 说明：光上面 Tailscale 那条，手机**能用 dsh web 但实时是慢的**（等刷新）。要**实时滚动**，需要走 SSH 隧道。所以第 3、4 步为「满血实时」版本。

**开启 Mac 的 Remote Login（SSH）：**
- **方法 A（图形，最稳）**：系统设置 → 通用 → 共享 → **远程登录** → 打开。
- **方法 B（命令行）**：
  ```bash
  sudo launchctl enable system/com.openssh.sshd
  sudo launchctl kickstart -k system/com.openssh.sshd
  ```
  > 若 `systemsetup -setremotelogin on` 报「需要完全磁盘访问」，就用上面的 launchctl 或图形界面，别用 systemsetup。

**验证（Mac 终端）：**
```bash
nc -z -w 3 127.0.0.1 22 && echo "SSH 已开"
```
能回 `SSH 已开` 即可（普通 `lsof` 看不到 22 是正常的，因为 socket 是 root 的）。

---

## 4. 手机 Termius 建「SSH + 端口转发」

**装 Termius**（App Store）。新建主机：

| 字段 | 值 |
|---|---|
| Host | `<你的Mac的tailnet IP>`（如 `100.83.243.80`） |
| Username | `<你的Mac用户名>`（Mac 上 `whoami`） |
| Port | `22` |
| Password | Mac 登录密码 |

> ⚠️ **坑**：有时手机把 `.ts.net` 域名解析到**错误的 IP**（出现 `198.18.x.x`、连上就 "end of file"）。**这时直接用 tailnet IP**（`tailscale status` 里 Mac 的 `100.x.x.x`），别用域名，最稳。

**加端口转发（Local）**：主机设置/连接里找到 **Port Forwarding → 类型 Local**：
| 字段 | 值 |
|---|---|
| Local port | `3080` |
| Destination host | `127.0.0.1` |
| Destination port | `3080` |

点保存。**连接这台主机**，转发就随连接生效。

> **免密（推荐，省得每次输密码）**：
> 1. 生成或粘贴一个 SSH Key（Mac 上 `ssh-keygen` 生成，公钥加进 `~/.ssh/authorized_keys`；私钥粘进 Termius 的 `SSH ID / Key`）。
> 2. Termius 里给主机设 `Username` + 选这把 Key，连接就不再要密码。

---

## 5. 手机打开 dsh web

**SSH 路（满血实时，主力）**：
```
http://127.0.0.1:3080
```
（首次用带 token 的：`http://127.0.0.1:3080/?token=<TOKEN>`；登录后会种下 30 天 cookie，之后直接开 `http://127.0.0.1:3080` 即可。）

**Tailscale 路（备用，实时慢）**：
```
https://<你的Mac>.ts.net/?token=<TOKEN>
```

**加到主屏**（推荐把【带 token 的网址】添加，这样每次点开都自动登录、不会 401）：
- Safari → 分享 → 添加到主屏幕。
- 用 **SSH 路**时主屏图标 = `http://127.0.0.1:3080/?token=...`；用 **Tailscale 路** = `https://...ts.net/?token=...`。

---

## 6. 日常使用：三件事保持活着

1. **Mac 开着**（dsh web 在跑）。
2. **SSH 路**：Termius 那台（带 Local Forwarding）**连着**；**Tailscale 路**：iPhone 的 Tailscale **连着**。
3. 主屏图标一点即进。

**手机端让隧道更稳（Termius 设置里）**：
- **Keep Alive Interval：60s**（已经默认，保持）。
- **Prevent Sleeping：ON**。

**切网络（WiFi↔流量）**：iOS 可能临时断一下，**回 Termius 点一下那台主机重连**即可（免密后就是纯点击，很快）。

**重启 dsh web 后**：token 会换 → 用第 2 步的 `~/dsh-phone-url.sh` 启动，自动打印新网址，更新主屏图标即可。

---

## 7. 验收清单（全过 = 完成）

- [ ] Mac 开 Tailscale 且魔法 DNS 开；iPhone 在 tailnet 里（`tailscale status` 能看到）。
- [ ] `pnpm dsh web --trusted-host ...` 跑起来，拿到 token 网址。
- [ ] Mac Remote Login 已开，`nc -z ... 22` 通。
- [ ] 手机 Termius 连上 Mac（免密更好），且 **Local Forwarding** 生效。
- [ ] 手机 `http://127.0.0.1:3080` 能打开 dsh web。
- [ ] 发消息，**回复实时滚动出现**。
- [ ] 传图：**复制一张照片 → 在 dsh web 输入框长按 → 粘贴**，图片进草稿、能发送。
- [ ] 主屏图标一键打开（带 token）。

---

## 附：快速参考（一句话版）
> **手机实时控制 DSH = 一条能到 Mac 回环端口的隧道 + dsh web 的 launch token。**
> 隧道二选一：**SSH 端口转发**（Termius Local，满血实时）或 **Tailscale Serve**（省事但实时慢）。
> 日常：Mac 开 dsh web（带 --trusted-host）+ 手机隧道连着 + 主屏图标（带 token）一点即进。

---

## 附录 · Windows 电脑 + 安卓手机（变体）

> 上文以 Mac+iPhone 为主。**电脑换 Windows、手机换安卓**时，核心机制不变（Tailscale 隧道 + dsh token），只改「手机端 App」和「电脑端开 SSH + 命令/路径」。

### 手机端：安卓（几乎照搬 iPhone 那套）
- **Tailscale**：安卓 App（Play 商店）→ 同账号 + 开 MagicDNS。
- **SSH App**：用 **Termius（安卓版）**，或更原生的 **JuiceSSH / Termux**（都支持 `-L` 本地端口转发）。端口转发同样是：**Local 3080 → 127.0.0.1:3080**。
- 手机浏览器开 `http://127.0.0.1:3080`、粘贴 SSH 私钥、**添加到主屏幕**（安卓：浏览器菜单 → 添加到主屏幕）——都和 iPhone 一样。
- token、实时、Keep Alive、切网重连——**完全一样**。

### 电脑端：Windows
- **Tailscale**：Windows 桌面版，登录 + MagicDNS + 拿 tailnet IP（`tailscale status`）。
- **DSH**：支持 Windows。用发布版：
  ```powershell
  npx @deepseek-ai/dsh web --trusted-host <你的Windows>.ts.net
  ```
  或源码版 `pnpm dsh web --trusted-host ...`（Node 用 Windows 安装版，不用 Homebrew）。
- **开 SSH 服务器（替代 Mac 的「远程登录」）→ OpenSSH Server**，用**管理员 PowerShell**：
  ```powershell
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
  Start-Service sshd
  Set-Service sshd -StartupType Automatic
  ```
  或 设置 → 应用 → 可选功能 → **OpenSSH 服务器**；确认防火墙放行 **22 端口**。
- **authorized_keys**：`C:\Users\<你>\.ssh\authorized_keys`；如果你是管理员账号，用 `C:\ProgramData\ssh\administrators_authorized_keys`（该文件权限要严格：仅 SYSTEM / Administrators）。
- 手机 Termius 连 **Windows 的 tailnet IP**（100.x），建 Local 3080 → 127.0.0.1:3080，**一样**。
- 手机开 `http://127.0.0.1:3080`（满血实时）→ **一样**。

### 命令/路径差异速查（Mac → Windows）
| Mac | Windows |
|---|---|
| `pnpm dsh web` | `npx @deepseek-ai/dsh web` 或 `pnpm dsh web` |
| 系统设置→共享→远程登录 / `launchctl` | `Add-WindowsCapability ... OpenSSH.Server` |
| `~/.ssh/authorized_keys` | `C:\Users\<你>\.ssh\authorized_keys` |
| Homebrew 装 Tailscale | 官网下载 .exe / `winget install tailscale` |
| `~/dsh-phone-url.sh`（zsh） | 用 PowerShell 写等价脚本，或看 `dsh web:` 打印的 token 网址 |

### 完全不变的部分
Tailscale、dsh web（`--trusted-host` / token / 实时）、端口转发概念、主屏一键、Keep Alive、切网重连——**一模一样**。

# DSH 手机远程控制 · 完整设置指南（Mac + iPhone，从零到满血实时）

> 本指南基于**实测跑通**的方案整理。目标：手机（iPhone）**实时**控制 Mac 上运行的 DeepSeek Harness（dsh web）。
> 两条路：**① Tailscale Serve（推荐主力：实时 + 熄屏不掉）**；**② SSH 端口转发（可选备用：实时，但 iOS 熄屏会断）**。二选一即可，也可都配。
> 全程只需：一台一直开机的电脑 + 一部手机 + 一个 Tailscale 账号。
> **本文以「Mac + iPhone」为主；安卓手机 / Windows 电脑的差异见文末「附录」，核心机制不变。文末另有「常见坑 & 排错（FAQ）」，遇到问题先查它。**

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

> **强烈推荐用脚本启动**（仓库里已带 `dsh-phone-url.sh`）：
> ```bash
> cp dsh-phone-url.sh ~/ && chmod +x ~/dsh-phone-url.sh
> ~/dsh-phone-url.sh
> ```
> 它会：① 若 3080 被旧实例占用先自动停掉（避免 `EADDRINUSE`）；② 用 **`--trusted-host`** 启动；③ 自动打印手机可用的两条网址（Tailscale / SSH）。
> ⚠️ **为什么别手敲 `pnpm dsh web`**：很容易漏掉 `--trusted-host`（→ 手机走 Tailscale 时 403），而且每次重启 token 会变、还得自己拼网址。**以后重启一律用这个脚本。**

### 2b. 配置 Tailscale Serve（让手机经 Tailscale 访问 dsh web）

**新装的话这步必做**：它把 `https://<你的Mac>.ts.net` 的 HTTPS 入口接到本机 3080。**必须是 HTTP 代理模式**（WebSocket 友好，实时才通）：
```bash
tailscale serve --tls-terminated-tcp=443 off 2>/dev/null || true   # 保险: 清掉可能的裸 TCP 旧配置
tailscale serve --bg --yes --https=443 http://127.0.0.1:3080
tailscale serve status      # 应显示: https://<Mac>.ts.net  →  proxy http://127.0.0.1:3080
```
> ⚠️ **别用 `--tls-terminated-tcp`（裸 TCP）模式**——它对本项目的 WebSocket 实时不友好（详见「坑 ④」）。

---

## 3. 给手机开 SSH 免密（**可选**，作为 SSH 备用路线的「满血实时」）

> **先看结论**：**Tailscale 路（第 1、2、5 步）现在也是实时的**（前提：Tailscale Serve 用 **HTTP 代理模式**，见下面「坑 ⑥」），而且因为它走 VPN 网络扩展，**手机熄屏也保持连接**——所以**推荐把 Tailscale 路当主力**。
> 本节 + 第 4 步的 **SSH 端口转发**是另一条实时路线（也满血实时），但 **iOS 熄屏后会挂起 Termius → 断**。两条都配好，互为备用。

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

**① Tailscale 路（推荐主力：实时 + 熄屏不掉）**：
```
https://<你的Mac>.ts.net/?token=<TOKEN>
```
- 前提：dsh web 带 `--trusted-host`，且 Tailscale Serve 是 **HTTP 代理模式**（见「坑 ⑥」）。
- 首次用带 token 的完整网址打开 → 自动登录、种下 30 天 cookie；之后开 `https://<你的Mac>.ts.net` 即可。
- **熄屏后 Tailscale（VPN 扩展）仍在后台 → 手机随时可开，不用重连。**

**② SSH 路（备用：实时，但需 Termius 隧道在；熄屏会断）**：
```
http://127.0.0.1:3080/?token=<TOKEN>
```

**加到主屏（关键，避免 401）**：把**【带 `?token=` 的完整网址】**添加，这样每次点图标都自动登录：
- Safari → 分享 → 添加到主屏幕。
- **Tailscale**：`https://<你的Mac>.ts.net/?token=...`；**SSH**：`http://127.0.0.1:3080/?token=...`。
- ⚠️ **别加"裸根"网址**（`https://...ts.net/` 不带 token）——cookie 一失效就 401。

---

## 6. 日常使用

**主力（Tailscale 路）**：只要 **Mac 开着（dsh web 在跑）+ 手机 Tailscale 连着**，点主屏图标即进，**熄屏也不掉**。

**备用（SSH 路）**：Termius 那台（带 Local Forwarding）连着时，开 `http://127.0.0.1:3080`。iPhone 熄屏会挂起 Termius → 断；**醒来后点一下主机重连**即可（免密后是纯点击）。
- 让隧道更稳（Termius 设置）：**Keep Alive Interval 60s** + **Prevent Sleeping ON**。

**重启 dsh web（token 会换，务必这样做）**：
```bash
~/dsh-phone-url.sh      # 自动停旧实例 + 带 --trusted-host 启动 + 打印新网址
```
拿到打印出的**新 token 网址**后：手机用**新网址**开一次 → 重新种 cookie → 更新主屏图标（旧 token 图标作废）。**别手敲 `pnpm dsh web`**（容易漏 `--trusted-host`）。

**切网络（WiFi↔流量）**：Tailscale 路基本无感（VPN 自己重连）；SSH 路可能断，回 Termius 点一下重连。

---

## 7. 验收清单（全过 = 完成）

- [ ] Mac 开 Tailscale 且 MagicDNS 开；iPhone 在 tailnet 里（`tailscale status` 能看到）。
- [ ] `~/dsh-phone-url.sh` 能启动 dsh web（带 `--trusted-host`），并打印 token 网址。
- [ ] Tailscale Serve 是 **HTTP 模式**（`tailscale serve status` 显示 `proxy http://127.0.0.1:3080`）。
- [ ] 手机 **Tailscale 路**：`https://<Mac>.ts.net/?token=...` 能打开 dsh web，**回复实时滚动**，**熄屏后仍可开**。
- [ ] （可选）Mac Remote Login 已开（`nc -z ... 22` 通），手机 Termius 连上（免密）+ Local Forwarding 生效 → `http://127.0.0.1:3080` 也能进。
- [ ] 主屏图标指向**带 token 的完整网址**，一键打开自动登录（不 401）。
- [ ] 传图：**复制一张照片 → 在 dsh web 输入框长按 → 粘贴**，图片进草稿、能发送。

---

## 8. 常见坑 & 排错（FAQ）

**① `listen EADDRINUSE: address already in use 127.0.0.1:3080`**
已有 dsh web 占着 3080。用 `~/dsh-phone-url.sh`（会**自动停掉旧实例**再启动）。

**② 手机打开是 401 / `dsh web authentication required; reopen the URL printed by dsh web`**
- 你开的是**裸根网址**或**旧 token 网址**。**必须用完整、带 `?token=` 的当前网址**开一次。
- **token 每进程唯一：重启 dsh web 就换**，旧 token 网址 + 旧主屏图标全部失效。
- 修法：`~/dsh-phone-url.sh` 拿**新网址** → 手机开一次 → **更新主屏图标**（用带 token 的完整网址）。

**③ 手机走 Tailscale 地址返回 403 forbidden**
dsh web 启动**漏了 `--trusted-host <你的Mac>.ts.net`**。用脚本重启。

**④ Tailscale 路实时不滚动 / 很慢**
Tailscale Serve 模式不对。必须是 **HTTP 代理模式**：
```bash
tailscale serve --tls-terminated-tcp=443 off || true        # 关掉错的裸 TCP 模式
tailscale serve --bg --yes --https=443 http://127.0.0.1:3080  # HTTP 模式（WebSocket 友好）
```
裸 TCP 模式（`--tls-terminated-tcp`）对 WebSocket 不友好 → 实时失效。

**⑤ iPhone 熄屏一段时间后 Termius 断连**
iOS 会挂起后台 App（普通 App 无法长时间后台保活）→ SSH 隧道断，**系统限制**。平时用 **Tailscale 路**（VPN 扩展，熄屏也保持）；SSH 路醒来点一下重连（免密=纯点击）。

**⑥ Termius 里手机把 `.ts.net` 解析到错误 IP（如 `198.18.x.x`），连上就 "end of file"**
改用 **Mac 的 tailnet IP**（`tailscale status` 里的 `100.x.x.x`）当 Host，别用域名。

**⑦ Termius 找不到「端口转发 / Port Forwarding」**
不在 Edit Host 里，要在**主机/连接**入口找 **Port Forwarding**，类型选 **Local**：Local `3080` → Destination `127.0.0.1:3080`。

**⑧ SSH 免密不生效（还要输密码）**
- **Private Key** 要粘**私钥**（`-----BEGIN OPENSSH PRIVATE KEY-----` 整段）；**Public Key** 才是 `ssh-ed25519 ...` 那行——**别粘反**。
- 主机要设 **Username** + 选上那把 Key。
- Mac 上确认公钥在 `~/.ssh/authorized_keys`（权限 `600`）。

**⑨ Mac 开 Remote Login 报「需要完全磁盘访问」**
别用 `sudo systemsetup -setremotelogin on`（需 Full Disk Access）。改用：
```bash
sudo launchctl enable system/com.openssh.sshd
sudo launchctl kickstart -k system/com.openssh.sshd
```
或 系统设置 → 通用 → 共享 → **远程登录**。

**⑩ `lsof -iTCP:22` 看不到 sshd，以为没开**
正常——socket 由 root/launchd 持有，普通权限看不到。用 `nc -z 127.0.0.1 22` 验证。

**⑪ 手机怎么传图？**
dsh web **没有上传按钮**。**复制一张图 → 在输入框长按 → 粘贴**（桌面端还可拖拽）。

**⑫ 下载 Tailscale/Termius 要不要 VPN/美区 Apple ID？**
一般不用（见第 0 步）。大陆 App Store 可能没有 Tailscale，需非大陆 Apple ID 或先有 VPN。

**⑬ dsh web 启动就弹浏览器，很烦**
启动命令加 `--no-open`。

**⑭ 忘了当前 token / 网址**
`~/dsh-phone-url.sh` 重启，会重新打印。

---

## 附：快速参考（一句话版）
> **手机实时控制 DSH = 一条能到 Mac 回环端口的隧道 + dsh web 的 launch token。**
> 隧道二选一：**Tailscale Serve（HTTP 模式）**——推荐，实时且**熄屏不掉**；或 **SSH 端口转发**——实时但熄屏会断。
> 日常：`~/dsh-phone-url.sh` 启动 dsh web（带 --trusted-host）→ 手机开**带 token 的完整网址**（加到主屏）→ 一点即进。

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

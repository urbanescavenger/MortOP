# MortOP 异常与修复记录

本文件记录每次发现的异常、根因、修复方式与验证结果。**新条目追加在最上面**，方便回看最近改动。

记录格式：

```
## YYYY-MM-DD 简短标题
- 环境:
- 现象:
- 根因:
- 修复:
- 验证:
- 提交/文件:
- 备注:
```

---

## 2026-11-17 muse-spark-open 451：容器 ollama 账号地区限制

- **现象**：158 容器 ollama 调 `muse-spark-open:cloud` → 451
  `not available in your region`；`glm-5.2` / `glm-5.3-flash` → 200
- **对比**：Windows 本机 ollama（直连出口同样是 `45.143.235.110` / Tokyo，JP）调
  `muse-spark-open` → **200**
- **出口验证**：从容器网络实测 egress = `45.143.235.110`（Tokyo/JP），
  与 Windows ollama 的直连出口完全相同，说明容器**确实走了代理**（不是没代理）
- **根因**：容器 ollama 的账号 key `/root/.ollama/id_ed25519`
  （sha256 `e5c9c8…`）与 Windows 的（`C01D03…`）不同。451 是 ollama.com 按
  **账号地区/权限** 拦截，不是 IP 或容器网络问题
- **修复（待确认）**：把 Windows 的 `id_ed25519` / `id_ed25519.pub` 同步到
  容器的 bind mount `/opt/docker/config/ollama` 后重启容器，或在容器里
  `ollama signin` 登录同一账号；也可以直接用 Windows 的 ollama 跑该模型
- **备注**：容器的 bind mount 是 `/opt/docker/config/ollama:/root/.ollama`；
  同步 key 属于敏感操作，操作前备份

---

## 2026-11-17 Ollama 代理路径 + Tailscale 重启持久性

- **环境**：158 passwall，ollama 容器 `172.24.0.6:11434`；另有一台
  `192.168.31.174` 也跑 ollama（0.40.16）
- **分流现状**：`passwall.OLLAMA` 的 `domain:ollama.com` 现在映射到
  `outboundTag "OLLAMA"` → `socks 127.0.0.1:1085` → 节点 `lSNYZ1Qp`（ollama 节点）。
  **容器出站到 ollama.com 已经走这个代理**
- **验证**：
  - 容器 `glm-5.2:cloud` → **200**（1.3s）
  - 容器 `glm-5.3-flash:cloud` → **200**（1.4s）
  - 容器 `muse-spark-open:cloud` → **451**（节点所在地区不支持该模型，不是链路问题）
  - `.174` 的 ollama 通过 158 转发，域名规则同样匹配 OLLAMA → 也走代理
- **入站**：158 容器的 11434 已加入 passwall `tcp_no_redir_ports` /
  `udp_no_redir_ports`，否则默认 TCP 重定向会抢在 Docker DNAT 之前把它送进代理
- **Tailscale 重启持久性**：`--netfilter-mode=off` 在当前 tailscaled 构建里不存在
  （`flag provided but not defined`），且 `fw_mode=off` 也挡不住它设置
  `src_valid_mark=1`。已在 `/etc/init.d/tailscale` 的 `start_service` 末尾加后台循环
  （8×2s）反复置 0；固件 uci-defaults 同步 patch。Tailscale 重启后 IPv4/IPv6、
  .174、158 容器均恢复正常
- **备注**：OLLAMA 分流是按域名全局生效的；若以后要让 .174 直连、只让容器走代理，
  需要按源 IP/MAC 做 ACL，当前没有这样做

---

## 2026-11-17 防火墙审计：Tailscale 转发缺失 + 残留规则

- **环境**：158，fw4/nftables
- **发现**：
  1. 关闭 Tailscale netfilter 后，`firewall` 缺少 `tailscale→wan` 和
     `tailscale→lan` forwarding；158 作为 exit node / 子网路由时，来自 tailnet
     的转发会被 `forward` 链的 policy drop 丢掉
  2. `fw4 check` 有 4 条告警：openclash include 路径不存在、SUNSUPPORT 规则/
     重定向已禁用、passwall include 的 `reload` 选项不支持
  3. `SUN SUPPORT` 规则（WAN 18325-18360 → 192.168.31.174）仍处于启用状态
  4. `docker` zone 的 `device` 列表是静态的 9 个 `br-*`；新 compose 网络的新
     bridge 不会自动加入，容器将无法 forward 到 WAN
  5. Tailscale 的 `ts-` iptables 规则仍残留（13/10 条），`fw_mode=off` 没有被
     完全执行；真正生效的是 `src_valid_mark=0`
- **修复**：
  - 添加 `tailscale→wan`、`tailscale→lan` forwarding
  - 删除 openclash include、禁用的 SUNSUPPORT rule/redirect、passwall include
    的 `reload` 选项
  - 备份 `/etc/config/firewall.bak-20261117`
- **验证**：`fw4 check` 只剩 miniupnpd 信息性提示；`forward_tailscale` 现在
  `jump accept_to_wan/lan`；IPv4/IPv6/Tailscale ping 均正常
- **待定**：docker 新网桥的 zone 同步（dockerd 自带 `uciadd` 或加通用
  172.16/12→wan/lan 规则）；`SUN SUPPORT` 规则是否还需要；`14573` 面板直开
  公网是否保留

---

## 2026-11-17 IPv6 国外站点不通（passwall nftables + Tailscale 冲突）

- **环境**：158（TMP 25.12.6 r33311，x86_64，fw4/nftables），passwall 26.11.11，
  tailscale 1.104.1，xray-ui 26.10.31
- **现象**：
  - `curl -6 https://www.cloudflare.com/cdn-cgi/trace`、`ipv6.icanhazip.com`、
    `google.com` 全部 `000`；`ipv6.baidu.com` 正常 `200`
  - `ping -6` 国外地址返回约 0.1ms（假象：passwall 把 IPv6 ICMP 重定向到本机）
  - xray-ui 的 29416 节点从 oracle 反测 TCP 可连、Reality 握手正常，但经隧道
    访问国外站点失败（服务端日志显示 freedom 出站拨到国外 IPv6 后被 reset）
  - 同一局域网 Windows 直接 `curl -6` 国外也是 `000`（浏览器能打开是走了 IPv4）
- **根因**：
  1. passwall 的 nftables 后端给 IPv6 TCP 规则生成的是 `tproxy to :1041`，
     缺少 `ip6` family；IPv6 包匹配不到代理，实际直连出去被 GFW reset
  2. Tailscale >= 1.96.4 启动时强制 `net.ipv4.conf.all.src_valid_mark=1`
     并添加 connmark 规则，破坏 passwall 的 TPROXY 策略路由
  3. `tcp_proxy_way=redirect` 时，1041 上的 tproxy inbound 只允许 UDP，
     IPv6 TCP 没有可用入口
- **修复**：
  - `/usr/share/passwall/nftables.sh`：`TPROXY` → `TPROXY6`（6 处）
  - UCI：`passwall.@global_forwarding[0].tcp_proxy_way='tproxy'`、`ipv6_tproxy='1'`
  - UCI：`tailscale.settings.fw_mode='off'`
  - `/etc/rc.local`：`sysctl -w net.ipv4.conf.all.src_valid_mark=0`
  - 固件化：`files/etc/uci-defaults/99-passwall-ipv6-tailscale.sh` +
    `files/etc/rc.local`（首次启动自动打补丁/写 UCI）
- **验证**：
  - 158：`google4=200`、`cloudflare6=200`、`baidu6=200`，
    出口 IPv6 `2a12:a301:2006::10ea`
  - Windows `curl.exe --noproxy "*"`：`cloudflare6=200`、`google4=200`，同出口
  - `tailscale ping nas` 0s；`tailscale ping oracle` 经 DERP(tok) 97ms
- **提交/文件**：`e07a645`（固件）；设备备份 `/etc/config/passwall.bak-ipv6-20261117`、
  `/etc/config/tailscale.bak-ipv6-20261117`、`/usr/share/passwall/nftables.sh.bak`
- **备注**：
  - TPROXY 模式 + Tailscale netfilter 同时开启时 IPv4 也会挂；必须同时把
    `src_valid_mark` 置 0（rc.local 在 tailscaled 之后再次设置）
  - 社区 issue：#4410（TPROXY 与 Tailscale 冲突）、#4418（25.12 IPv6 TPROXY）
  - passwall 通过 apk 升级会覆盖 `nftables.sh`，补丁会丢；需要重新升级固件或重打

## 2026-11-17 SMB：ksmbd 与 samba4 抢 445

- **环境**：158，OpenWrt 25.12
- **现象**：dmesg `ksmbd: Failed to bind socket: -98`；`smbd` 占着 445/139；
  ksmbd 配置的 `config` 共享不可用；`ksmbd.mountd` 出现两个进程（父+子）
- **根因**：`.config` 同时选了 `ksmbd-server` + `samba4-server`（`luci-app-samba4`），
  两者都是 S98 启动、抢同一个 445；samba4 先绑定成功，且它自己没有任何共享
- **修复**：只留 ksmbd，加 `luci-app-ksmbd` 面板，去掉 samba4（`43454c7`）；
  设备上 `/etc/init.d/samba4 stop && disable` + `/etc/init.d/ksmbd restart`
- **验证**：445 由 ksmbd 内核监听；`ksmbd.control -l` 显示 `config`；
  `wsdd2` 继续使用 `/etc/ksmbd/ksmbd.conf` 做 Windows 发现
- **备注**：旧 LEDE 的 .config 也有 `samba36 + ksmbd` 双选，属于老问题；
  共享目录 `/opt/docker/config` 同时由 NFS 导出

## 2026-11-17 Tailscale 控制面 long-poll 超时

- **环境**：158，tailscale 1.104.1
- **现象**：对端显示 offline；日志每 2 分钟
  `map response long-poll timed out` / `PollNetMap: context canceled`；
  抓到一条到 `192.200.0.115:443` 的 ESTABLISHED，Send-Q 约 79KB 发不出去
- **根因**：控制面长连接被卡死（具体链路未完全定位）
- **修复**：`/etc/init.d/tailscale restart` 后恢复
- **验证**：本机节点变回 `idle`；新进程 map 错误 0；`tailscale ping nas/oracle` 正常
- **备注**：东京 DERP 走 IPv6 仍有 `connection reset by peer`，属独立的国外 IPv6 问题，
  见上面的 IPv6 条目

## 2026-11-17 iStore 安装 Tailscale 社区版失败

- **现象**：`apk add app-meta-tailscale-community` 报
  `luci-app-tailscale-community (no such package)` /
  `luci-i18n-tailscale-community-zh-cn (no such package)`
- **根因**：iStore 的 apk 源里 `meta` 有元包，但 `nas_luci` 只有旧的
  `luci-app-tailscaler`，新插件没有发布到 apk 仓库
- **修复**：编进固件（`8a0dbc7`，`luci-app-tailscale-community=y`）；
  设备上无需重装现有 `tailscale 1.104.1`
- **备注**：iStore 的“Tailscale（社区版）”是带 LuCI 的元包；旧的 0.0.6 已废弃

## 2026-11-17 docker-data 的 rc.d 符号链接在工作区丢失

- **现象**：`git status` 显示 `D files/etc/rc.d/S15docker-data`，但设备上该
  启动脚本存在，`/opt/docker` 也正常挂载
- **根因**：历史提交 `def0807` 特意添加，从未被删除；Windows 工作区
  `core.symlinks=false` 导致 symlink 未落地/丢失
- **修复**：恢复为内容 `../init.d/docker-data` 的普通文件（blob hash 与 index 一致），
  不产生提交
- **备注**：不要用 `git add -A` 把这个删除带进提交，否则下次编译会丢开机挂载

## 待观察 / 未修

- Caddy 访问日志以 `daemon.err` 写入 logread，128KB ring 被刷满；建议给站点配
  `log { output file ... }`
- firewall 残留 openclash include、SUN SUPPORT 规则，每次 reload 报警告
- 158 的 hostname 仍是 `MortOP-160`（`system.@system[0].hostname`），仅影响显示和
  Tailscale 节点名
- timezone 为 `GMT0`（与旧系统一致，非本次回归）
- `14573`（xray-ui 面板）已加入 `Open XUI` 直接对公网 IPv6 开放；Caddy 另有
  `xui.19961226.xyz:57126` 反代，建议评估是否需要直开

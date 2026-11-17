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

## 2026-11-17 LuCI 切到 design 主题后整页 500：主题与当前 LuCI 不兼容（已修复）

- **环境**：158，x86_64 ext4 镜像；LuCI 25.12；`luci-theme-design 5.8.0~20240106`
- **现象**：在 LuCI“主题”列表切到 design 后，任意页面报
  `dispatcher.lua:68: attempt to index global '__entries' (a nil value)` /
  `Failed to execute template 'themes/design/header'`，LuCI 不可用
- **根因**：design 是 2023 年的第三方主题，`header.htm` 仍按旧 LuCI 的全局
  `entries` 逻辑渲染，而当前 dispatcher 的上下文已改为 `__entries`（仅在分发
  期间赋值），主题在登录页阶段就触发 nil 索引
- **为什么固件里会有**：`.config` 里虽然写着
  `# CONFIG_PACKAGE_luci-theme-design is not set`，但同文件仍选了
  `CONFIG_PACKAGE_luci-app-design-config=y`；该包的依赖是
  `luci-theme-design`（`D: libc luci-compat luci-lua-runtime luci-theme-design`），
  镜像构建时会把主题一起拉进来。与“还原配置”无关，是主题列表里能选到它
- **修复**：
  - 设备：`uci set luci.main.mediaurlbase='/luci-static/argon'`，清
    `/tmp/luci-*cache*`，重启 uhttpd；已验证 LuCI 正常渲染
  - 构建：`.config` 关掉 `luci-app-design-config` 与
    `luci-i18n-design-config-zh-cn`，让 design 主题不再被依赖拉入；
    默认主题仍是 Argon（`99-set-argon-theme.sh`）
- **验证**：切回 argon 后 `curl http://127.0.0.1/cgi-bin/luci/` 返回正常 LuCI
  页面（不再出现 Unhandled exception）
- **备注**：当前设备镜像里仍装着 design 包（老镜像自带），选中它仍会崩；
  下次刷入新固件后不再存在。需要的话可 `apk del luci-app-design-config
  luci-i18n-design-config-zh-cn luci-theme-design` 立即移除

---

## 2026-11-17 LuCI Netdata 仪表盘“连接已重置”：netdata ACL 不含 Tailscale 网段（已修复）

- **环境**：158（hostname 仍为 `MortOP-160`），netdata 1.33.1，Tailscale 1.104.1；
  PC 在 LAN 上但到 `192.168.31.0/24` 的流量被 Tailscale 子网路由接管（源地址 `100.93.112.84`）
- **现象**：LuCI `系统 → Netdata` 页面本身正常，内嵌仪表盘区域空白，
  显示 `连接已重置。`；直接从 PC 访问 `http://192.168.31.158:19999/` 同样失败
- **根因**：该 LuCI 插件只是把
  `http://<window.location.hostname>:19999` 塞进 iframe，没有问题；
  失败的是 netdata 自身。OpenWrt 的 `/etc/netdata/netdata.conf` 只允许
  `localhost` + RFC1918，Tailscale 客户端源地址是 `100.64.0.0/10`；
  netdata 在 `accept()` 层就关闭不匹配的连接（官方文档原话：
  “connected and disconnected immediately, without reading even a single byte”），
  浏览器因此显示连接被重置，而不是 403
- **修复**：在设备上给 `[web]` 的 `allow connections from` 和
  `allow dashboard from` 追加 `100.* fd*`，重启 netdata。
  `/etc/netdata/` 已在 netdata 包的 `/lib/upgrade/keep.d/netdata` 保留清单里，
  改动会随“保留配置”升级和备份/还原自动带回来，所以**不写 uci-defaults 出厂脚本**
  （缺这条只影响 Tailscale 访问，出厂 LAN 状态本身正常，不属于“不补会破坏出厂运行”的例外）
- **验证**：路由器本机 `127.0.0.1:19999` / `192.168.31.158:19999` / `100.108.85.101:19999`
  全部 200；PC（经 Tailscale，源 `100.x`）与独立节点 oracle 访问均为 200；
  修复前两者均为 `Connection was reset`，而 LuCI 80 端口一直正常
- **提交/文件**：无仓库改动；设备端 `/etc/netdata/netdata.conf`，
  原文件备份 `/etc/netdata/netdata.conf.bak.<时间戳>`
- **备注**：插件把 iframe 写死为 `http://…:19999`。若 LuCI 用 HTTPS 打开，
  即使 ACL 放行，Chrome 也会按混合内容拦截；此现象不是本次的连接重置。
  备份必须是修复之后做的，旧备份会带回旧 ACL

---

## 2026-11-17 双 AGH 海外实例无法走代理：容器改 host 网络 + DoH 用 IPv4 字面量（已修复）

- **环境**：双 AdGuardHome —— 宿主 AGH（`5553`，国内上游 `223.5.5.5`/`119.29.29.29`，
  `direct_dns_tcp`）+ Docker AGH（`6653`，海外上游 DoH cloudflare/google，
  `remote_dns`）；`dns_redirect='1'`
- **现象**：passwall 启动后 Google 域名解析超时（`nslookup www.google.com 127.0.0.1`
  timeout，百度正常），passwall 自测失败；但节点/隧道正常（`socks5h` 经
  `127.0.0.1:1070` → Google `204`，`url_test_node` → `204`）
- **根因**：海外 AGH 在 Docker 网桥里，出站不进 passwall 的“路由器本机代理”，
  它的 DoH 是直连 → 被墙。AGH 日志 `failed to init http client: timeout exceeded`；
  passwall xray 日志 `failed to lookup ... at server TCP//127.0.0.1:6653 >
  record not found`。另外 bootstrap `223.5.5.5` 对 `dns.google` /
  `dns.cloudflare.com` 只返回 IPv6（`2001:4860:4860::8844`、
  `2803:f800:53::8`），容器直连 IPv6 同样不通
- **修复**：`/etc/docker-stacks/adguard/docker-compose.yml` 加
  `network_mode: host`、删 `ports:`；海外 AGH 上游改成 IPv4 字面量
  `https://1.1.1.1/dns-query` + `https://8.8.8.8/dns-query`，`fallback_dns` 清空
- **验证**：`nslookup www.google.com 127.0.0.1` → `142.251.x`；路由器本机
  `curl https://www.google.com/generate_204` → `204`（0.44s）；passwall
  `test_url` → `200`、`url_test_node` → `204`；AGH 启动后无 error/timeout
- **备份**：`docker-compose.yml.bak-20261117-144024`、
  `AdGuardHome.yaml.bak-20261117-144024`
- **备注**：host 模式只占 `3000/tcp` 与 `6653/tcp+udp`（原本就是它自己的
  docker-proxy 占着），与 uhttpd `80/443`、dnsmasq `53`、宿主 AGH `5553`、
  avahi/umdns `5353` 均不冲突；社区双 AGH 教程同样用 `--net=host`。
  AGH 原生不支持给 DNS 上游配代理（`http_proxy` 只管过滤规则下载）

---

## 2026-11-17 经 xray-ui 代理访问本地 Jellyfin 超时：Xray freedom 默认黑洞私有 IP（已修复）

- **环境**：xray-ui 26.10.31（`juestnow/xray-ui`，`network_mode: host`，内置 Xray 26.10.31）
- **现象**：客户端经 x-ui 入站访问 `http://192.168.31.158:8096` 恒定超时
  （经 socks 实测 `000`/rc=28，约 50s），同期公网
  `www.gstatic.com/generate_204` 正常 `204`；用户反馈"以前是可以的"
- **根因**：Xray-core 自 26.4.15 起给 freedom 出站加了默认 finalRule
  （`defaultBlockPrivateRule`）：凡是从 proxy 入站（vless/vmess 等）进来的目标，
  命中私有/保留 IP 一律 blackhole，随机保持 30–90s。服务端 error.log：
  `proxy/freedom: blocked target: tcp:192.168.31.158:8096, blackholing connection for 52s`。
  路由里的 `192.168.31.0/24 → direct` 规则**救不了**——黑洞发生在 freedom 出站内部
- **修复**：面板 DB `settings.xrayTemplateConfig` 的 freedom 出站加
  `"settings": {"finalRules": [{"action": "allow", "ip": ["geoip:private"]}]}`
  （面板 UI → 设置 → Xray 配置模板也可改同一处）；停容器改库、删残留
  `-wal/-shm`、启动，新配置已生成进 `/app/bin/config.json`
- **验证**：本机 Xray 客户端经 27469 入站 + socks 访问 Jellyfin：修复前 `000`
  （rc=28），修复后 `302`，跟随跳转 `200`（`/web/`，0.03s）；服务端不再出现
  blocked target
- **备份**：`/opt/docker/config/xray-ui/etc/xray-ui.db.bak-20261117-140849`
- **备注**：`geoip:private` 覆盖 RFC1918/loopback/ULA；Tailscale 的
  `100.64.0.0/10` 不在其中，若需经代理访问 TS 地址要再显式加该网段。
  上游 3x-ui 同款修复：[commit d7f47d8](https://github.com/MHSanaei/3x-ui/commit/d7f47d8b)；
  案例 [Discussion #6157](https://github.com/XTLS/Xray-core/discussions/6157)、
  [freedom 文档](https://xtls.github.io/en/config/outbounds/freedom.html)

---

## 2026-11-17 收起 14573 直连 + Caddy 访问日志落盘

- **14573（xray-ui 面板）**：从 `Open XUI` 的 WAN 规则移除，只保留
  `27469 27180 29416`；oracle 实测 `14573 closed`，而
  `https://xui.19961226.xyz:57126/` 仍 **200**（Caddy 反代正常）
- **Caddy 日志**：全局 `log` 块把默认日志重定向到
  `/opt/docker/config/caddy/log/access.log`（`roll_size 100MiB`、`roll_keep 5`、
  `roll_keep_for 720h`）；per-site 的 webdav 日志仍写各自文件
- **验证**：`caddy validate` 通过；logread 里 `http.log.access` 不再增长
  （访问日志写入文件），文件中能看到真实请求
- **备份**：`/etc/caddy/Caddyfile.bak-20261117`
- **备注**：全局 log 会把 Caddy 的运行日志也写到该文件；启动错误仍会经 procd
  进 logread

---

## 2026-11-17 Docker 新网络无法入区：源网段放行（已采用）

- **风险**：Docker 新建网络会生成新的 `br-<id>`，不会自动加入
  `firewall.docker.device`；该网络里的容器无法 forward 到 WAN
- **当前状态**：已有 9 个 `br-*` 全部在 zone 和 fw4 jump 列表里；新网络由
  源网段规则覆盖，**不需要再逐个加 zone**
- **社区方案**：不要逐桥 `uci add_list`（dockerd 的 `uciadd` hook 正在被上游修，
  openwrt/packages#29963）；用源网段规则或 wildcard `br-*` 匹配
- **采用**：firewall rule `src='*'`、`src_ip='172.16.0.0/12'`、`dest='wan'`、
  `target='ACCEPT'`（命名 section `firewall.docker_forward`，名字
  `Allow-Docker-Forward`）
- **验证**：
  - `test-wild` → `br-bce009dc6836`（不在 zone）：加规则前无出网，加规则后正常
  - `test-wild2` → `br-6d91508555fd`（不在 zone）：规则生效后出口
    `45.143.235.110`，正常
- **固件**：`files/etc/uci-defaults/98-docker-forward.sh`（已存在同名规则则跳过）
- **备注**：规则只生成 tcp/udp；如需容器 ICMP，可加 `proto 'all'`
- **备注**：规则只生成 tcp/udp；如需容器 ICMP，可加 `proto 'all'`

---

## 2026-11-17 LAN 客户端访问 docker 发布端口全 refused：缺 tailscale→docker 转发（已修复）

- **现象**：LAN/TS 客户端访问 `192.168.31.158` 的 DNAT 发布端口
  （8096 Jellyfin / 8123 HA / 11434 / 6653 / 1883）一律 Connection refused
  （恒定 ~2s）；直听端口（SSH:22、caddy:8443）和 `100.108.85.101` 直访均正常
- **误导**：时间上与 passwall 开关重合，一度怀疑 passwall；A/B 实测
  （passwall 开/关两种状态同样失败）排除
- **排查**：iptables DNAT 计数器在涨、fw4 forward_lan `Allow-LAN-to-Docker`
  accept 计数正常，但 conntrack 无客户端条目 → 源不是 br-lan。PC 上发现
  `192.168.31.0/24 via 100.100.100.100 metric 5`（Tailscale 子网路由）：
  流量被劫进隧道，从 `tailscale0` 进来（netstat 里可见
  `:22 ← 100.93.112.84` 的 SSH 连接）
- **根因**：11-17 早些的防火墙审计补了 `tailscale→wan`、`tailscale→lan`，
  漏了 `tailscale→docker`；forward 链 policy drop 下落到
  `handle_reject → tcp reset`
- **修复**：`uci add firewall forwarding`（src=tailscale，dest=docker）+ reload；
  `forward_tailscale` 链新增 `jump accept_to_docker`（oif 10 个 br-*），计数器走包
- **社区依据**：转发是单向的，zone/forwarding 需逐方向配
  （[tailscale.tw OpenWrt 指南](https://tailscale.tw/platforms/openwrt/index.md)、
  [iStoreOS #2574](https://github.com/istoreos/istoreos/issues/2574)）；
  Tailscale 对"客户端直连该网段仍接受子网路由导致 hairpin"是无官方开关的已知行为
  （[官方 FAQ](https://tailscale.com/docs/reference/troubleshooting/network-configuration/lan-traffic-overlapping-subnets)）
- **遗留**：PC/TS 客户端侧的子网路由 hairpin 隐患仍在（accept-routes 关闭可根治）；
  本条规则建议固件化（`99-*-tailscale-docker.sh`）；passwall 当前停在关闭态

---

## 2026-11-17 muse-spark-open 451：容器内模型未安装（已解决）

- **现象**：158 容器 ollama 调 `muse-spark-open:cloud` → 451
  `not available in your region`；`glm-5.2` / `glm-5.3-flash` → 200
- **误导**：一度怀疑容器账号 key 与 Windows 不同（`e5c9c8…` vs `C01D03…`），
  以及代理/地区问题；实测容器出口 `45.143.235.110`（Tokyo/JP）与 Windows 相同
- **真正根因**：容器内**没有安装** `muse-spark-open:cloud`。`:cloud` 模型也需要在
  对应 ollama 实例里 `ollama pull` 一次；未安装时请求会向主站拉取并返回 451
- **修复**：在容器里安装/拉取该模型（用户刚装；`POST /api/pull` 返回
  `{"status":"success"}`），**不需要改 key**
- **验证**：`muse-spark-open:cloud` generate → **200**，正常返回
- **备注**：容器账号、出口、passwall OLLAMA 分流都正常；以后先 `ollama list`
  确认模型是否已安装

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
  - 容器 `muse-spark-open:cloud` → **451**（当时模型未安装；`ollama pull` 后 **200**）
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

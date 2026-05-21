# ip_derper

一个用于快速构建与运行 **Tailscale DERP Relay** 的 Docker 化项目，适合自建轻量中继节点。

> 本项目 fork 自 [yangchuansheng/ip_derper](https://github.com/yangchuansheng/ip_derper)，在其基础上补充了更易读的中文说明与配置注释，方便二次维护与部署。

## 项目结构

- `Dockerfile`：两阶段构建，先编译 `derper`，再在运行镜像中启动。
- `build_cert.sh`：按传入 IP/主机名生成自签证书（含 SAN）。
- `.gitmodules`：管理 `tailscale` 子模块来源。
- `.github/workflows/main.yml`：常规构建/同步流程（按仓库实际策略执行）。
- `.github/workflows/submodule-sync.yml`：子模块同步流程。

## 当前推荐部署方式（与现网一致）

目前推荐使用 **docker-compose + host network + 独立 tailscale sidecar** 的组合：

- `tailscale` 容器只负责提供本地 tailscaled socket（`/var/run/tailscale/tailscaled.sock`）。
- `derper` 容器通过挂载同一 socket，实现 `--verify-clients` 所需的本机 Tailscale 身份校验。
- 两个容器都使用 `network_mode: host`，减少 NAT 复杂度，避免 UDP 穿透链路额外损耗。

> 安全提示：
> - 不要把 `TS_AUTHKEY` 明文提交到仓库。
> - 以下示例已将公网 IP、AuthKey 脱敏，请替换成你自己的值。

### docker-compose.yml

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: derp-node
    command: tailscaled --socket=/var/run/tailscale/tailscaled.sock --tun=userspace-networking
    environment:
      - TS_AUTHKEY=tskey-auth-REDACTED
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_NETFILTER_MODE=off
      - TS_ROUTES=
      - TS_ACCEPT_DNS=false
    volumes:
      - ./tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
      - /var/run/tailscale:/var/run/tailscale
    cap_add:
      - net_admin
      - sys_module
    network_mode: host
    restart: unless-stopped

  derper:
    image: ghcr.io/giao4giao/ip-derper:sha-a46da4d
    container_name: derper
    restart: always
    network_mode: host
    depends_on:
      - tailscale
    environment:
      - DERP_STUN_PORT=39285
      - DERP_ADDR=:42455
      - DERP_HOST=<YOUR_PUBLIC_IP>
      - DERP_CERTS=/app/certs
      - DERP_VERIFY_CLIENTS=true
    volumes:
      - /var/run/tailscale:/var/run/tailscale
```

## 为什么这样部署

### 1) tailscale 采用 userspace networking

`tailscaled --tun=userspace-networking` 可以避免修改宿主机默认路由与 DNS，适合已在线上运行其他网络服务的机器。

配套参数含义：

- `TS_NETFILTER_MODE=off`：不接管 iptables/nftables。
- `TS_ROUTES=`：不通告子网路由。
- `TS_ACCEPT_DNS=false`：不改写宿主机 DNS。

### 2) derper 开启客户端身份校验

`DERP_VERIFY_CLIENTS=true` 对应 derper 的 `--verify-clients` 行为：

- 仅允许能够被本机 tailscaled 验证身份的 Tailscale 客户端使用该 DERP。
- 适合私有网络/组织内网场景，避免被公开滥用。

### 3) 自定义端口

该部署中使用：

- DERP 端口：`42455/tcp`
- STUN 端口：`39285/udp`

请确保云防火墙与系统防火墙均已放行对应端口。

## 客户端 DERPMap 配置示例

以下是与上面部署端口一致的 `derpMap` 示例：

```json
"derpMap": {
  "OmitDefaultRegions": false,
  "Regions": {
    "901": {
      "RegionID": 901,
      "RegionCode": "HangZhou",
      "RegionName": "China",
      "Nodes": [
        {
          "Name": "HangZhou",
          "RegionID": 901,
          "HostName": "<YOUR_PUBLIC_IP>",
          "IPv4": "<YOUR_PUBLIC_IP>",
          "DERPPort": 42455,
          "STUNPort": 39285,
          "CanPort80": false,
          "InsecureForTests": true
        }
      ]
    }
  }
}
```

> 说明：
> - `InsecureForTests` 建议仅用于测试阶段；生产可结合正式证书与严格校验策略。
> - 如果你希望完全只走自建 DERP，可再按需把 `OmitDefaultRegions` 调整为 `true`。

## 仍可选的本地构建方式

如果你不想直接使用 GHCR 镜像，也可以本地构建：

### 1) 初始化子模块

```bash
git submodule update --init --recursive
```

### 2) 构建镜像

```bash
docker build -t ip-derper:latest .
```

### 3) 运行容器（简化示例）

```bash
docker run -d --name ip-derper \
  -p 80:80 \
  -p 443:443/tcp \
  -p 443:443/udp \
  -e DERP_HOST=<YOUR_PUBLIC_IP_OR_DOMAIN> \
  -e DERP_ADDR=:443 \
  -e DERP_HTTP_PORT=80 \
  -e DERP_STUN=true \
  -e DERP_VERIFY_CLIENTS=false \
  ip-derper:latest
```

## 关键环境变量

- `DERP_HOST`：DERP 对外主机名/IP（会用于证书 CN/SAN）。
- `DERP_ADDR`：DERP 服务监听地址，默认 `:443`。
- `DERP_HTTP_PORT`：HTTP 端口，默认 `80`。
- `DERP_STUN_PORT`：STUN 监听端口（在当前部署中显式指定）。
- `DERP_CERTS`：证书目录，默认 `/app/certs/`。
- `DERP_STUN`：是否启用 STUN（当镜像支持该变量时生效）。
- `DERP_VERIFY_CLIENTS`：是否校验客户端，生产建议 `true`。

## 证书说明

- 启动时执行 `build_cert.sh` 自动生成 730 天有效期的自签名证书。
- 若生产环境有正式证书，建议改造为挂载外部证书并关闭自签流程。
- 若客户端启用了严格证书校验，建议使用域名 + 受信 CA 证书。

## 常见问题

### 1) DERP_HOST 写域名还是 IP？

都可以；当前脚本以 IP SAN 方式写入。若使用域名，建议在证书中增加 DNS SAN 并使用正式证书。

### 2) 为什么要拆成 tailscale + derper 两个容器？

因为 `verify-clients` 依赖 tailscaled 提供本地身份服务。拆分后职责更清晰，也更容易单独升级 tailscale 与 derper。

### 3) 为什么用 host network？

DERP/STUN 对网络路径与 UDP 可达性较敏感，host 网络通常更直接，问题定位也更简单。

## 致谢

感谢 [yangchuansheng/ip_derper](https://github.com/yangchuansheng/ip_derper) 提供的原始实现。

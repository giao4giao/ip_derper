# ip_derper

一个用于快速构建与运行 **Tailscale DERP Relay** 的 Docker 化项目，适合自建轻量中继节点。

> 本项目 fork 自 [yangchuansheng/ip_derper](https://github.com/yangchuansheng/ip_derper)，在其基础上补充了更易读的中文说明与配置注释，方便二次维护与部署。

## 项目结构

- `Dockerfile`：两阶段构建，先编译 `derper`，再在运行镜像中启动。
- `build_cert.sh`：按传入 IP/主机名生成自签证书（含 SAN）。
- `.gitmodules`：管理 `tailscale` 子模块来源。
- `.github/workflows/main.yml`：常规构建/同步流程（按仓库实际策略执行）。
- `.github/workflows/submodule-sync.yml`：子模块同步流程。

## 运行原理

1. 构建阶段基于 Golang 镜像编译 `tailscale/cmd/derper`。
2. 运行阶段基于 Ubuntu，启动时自动生成自签证书。
3. 最终以手动证书模式启动 DERP 服务，并可选开启 STUN。

## 快速开始

### 1) 初始化子模块

```bash
git submodule update --init --recursive
```

### 2) 构建镜像

```bash
docker build -t ip-derper:latest .
```

### 3) 运行容器

```bash
docker run -d --name ip-derper \
  -p 80:80 \
  -p 443:443/tcp \
  -p 443:443/udp \
  -e DERP_HOST=你的公网IP \
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
- `DERP_CERTS`：证书目录，默认 `/app/certs/`。
- `DERP_STUN`：是否启用 STUN，默认 `true`。
- `DERP_VERIFY_CLIENTS`：是否校验客户端，默认 `false`。

## 证书说明

- 启动时执行 `build_cert.sh` 自动生成 730 天有效期的自签名证书。
- 若生产环境有正式证书，建议改造为挂载外部证书并关闭自签流程。

## 常见问题

### 1) DERP_HOST 写域名还是 IP？

都可以；当前脚本以 IP SAN 方式写入，若使用域名建议进一步扩展脚本，增加 DNS SAN。

### 2) 为什么要 fork 原仓库？

核心逻辑仍沿用上游设计，fork 的主要目的是便于按团队习惯维护、添加中文注释并扩展自动化流程。

## 致谢

感谢 [yangchuansheng/ip_derper](https://github.com/yangchuansheng/ip_derper) 提供的原始实现。

# ===== 构建阶段：编译 derper 二进制 =====
FROM golang:latest AS builder

LABEL org.opencontainers.image.source https://github.com/giao4giao/ip_derper

WORKDIR /app

# 将 tailscale 子模块拷入构建上下文
ADD tailscale /app/tailscale

# 编译修改后的 derper：
# - CGO_ENABLED=0 方便得到静态可移植二进制
# - -s -w 减小体积
RUN cd /app/tailscale/cmd/derper && \
    CGO_ENABLED=0 /usr/local/go/bin/go build -buildvcs=false -ldflags "-s -w" -o /app/derper && \
    cd /app && \
    rm -rf /app/tailscale

# ===== 运行阶段：最小依赖启动 derper =====
FROM ubuntu:20.04
WORKDIR /app

# ========= CONFIG =========
# derper 参数（可在 docker run -e 中覆盖）
ENV DERP_ADDR=:443
ENV DERP_HTTP_PORT=80
ENV DERP_HOST=127.0.0.1
ENV DERP_CERTS=/app/certs
ENV DERP_STUN=true
ENV DERP_STUN_PORT=3478
ENV DERP_VERIFY_CLIENTS=false
# ==========================

# 安装运行时依赖：
# - openssl: 生成自签证书
# - curl: 常用于健康检查/调试
RUN apt-get update && \
    apt-get install -y openssl curl

COPY build_cert.sh /app/
COPY --from=builder /app/derper /app/derper

# 启动流程：
# 1) 先按 DERP_HOST 生成自签证书
# 2) 再以手动证书模式启动 derper
CMD bash /app/build_cert.sh "$DERP_HOST" "$DERP_CERTS" /app/san.conf && \
    /app/derper --hostname="$DERP_HOST" \
    --certmode=manual \
    --certdir="$DERP_CERTS" \
    --stun="$DERP_STUN" \
    --stun-port="$DERP_STUN_PORT" \
    --a="$DERP_ADDR" \
    --http-port="$DERP_HTTP_PORT" \
    --verify-clients="$DERP_VERIFY_CLIENTS"

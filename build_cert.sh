#!/bin/bash

# 传入参数：证书主机（通常是公网 IP 或域名）
CERT_HOST=$1
# 证书输出目录
CERT_DIR=$2
# openssl 配置文件输出路径
CONF_FILE=$3

# 判断是 IPv4 还是域名，自动写入对应 SAN
if echo "$CERT_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    SAN="IP.1 = $CERT_HOST"
else
    SAN="DNS.1 = $CERT_HOST"
fi

# 生成最小可用的 openssl 配置：
# - 关闭交互输入（prompt = no）
# - 同时写入 req_ext 与 v3_req，确保 SAN 生效
echo "[req]
default_bits  = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
countryName = XX
stateOrProvinceName = N/A
localityName = N/A
organizationName = Self-signed certificate
commonName = $CERT_HOST: Self-signed certificate

[req_ext]
subjectAltName = @alt_names

[v3_req]
subjectAltName = @alt_names

[alt_names]
$SAN
" > "$CONF_FILE"

# 确保证书目录存在
mkdir -p "$CERT_DIR"
# 生成 730 天有效期的自签证书与私钥
openssl req -x509 -nodes -days 730 -newkey rsa:2048 -keyout "$CERT_DIR/$CERT_HOST.key" -out "$CERT_DIR/$CERT_HOST.crt" -config "$CONF_FILE"

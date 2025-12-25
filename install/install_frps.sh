#!/bin/bash

# ==================================================
# FRP Server (frps) 快速安装脚本
# 支持架构: amd64, arm64
# 功能: 下载最新版, 配置 Token/Dashboard, Systemd 自启
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 权限运行此脚本。${PLAIN}" 
   exit 1
fi

echo -e "${YELLOW}正在检测系统架构...${PLAIN}"

# 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    *)
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
        ;;
esac
echo -e "系统架构: ${GREEN}$ARCH${PLAIN}"

# 依赖检查
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null || ! command -v tar &> /dev/null; then
    echo -e "${YELLOW}正在安装依赖 (curl, jq, tar)...${PLAIN}"
    if [ -x "$(command -v apt)" ]; then
        apt update && apt install -y curl jq tar
    elif [ -x "$(command -v yum)" ]; then
        yum install -y curl jq tar
    else
        echo -e "${RED}无法自动安装依赖，请手动安装 curl, jq 和 tar。${PLAIN}"
        exit 1
    fi
fi

# =================配置向导=================
echo -e "------------------------------------------------"
echo -e "请根据提示配置 FRP 服务端 (回车使用默认值)"
echo -e "------------------------------------------------"

# 1. 绑定端口
read -p "请输入 FRP 绑定端口 (默认 7000): " BIND_PORT
[[ -z "$BIND_PORT" ]] && BIND_PORT=7000

# 2. 身份验证 Token (生成随机密码)
DEFAULT_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
read -p "请输入连接密钥 Token (默认随机生成): " AUTH_TOKEN
[[ -z "$AUTH_TOKEN" ]] && AUTH_TOKEN=$DEFAULT_TOKEN

# 3. 仪表盘端口
read -p "请输入仪表盘(Dashboard)端口 (默认 7500): " DASH_PORT
[[ -z "$DASH_PORT" ]] && DASH_PORT=7500

# 4. 仪表盘账号密码
read -p "请输入仪表盘用户名 (默认 admin): " DASH_USER
[[ -z "$DASH_USER" ]] && DASH_USER="admin"

read -p "请输入仪表盘密码 (默认 admin): " DASH_PWD
[[ -z "$DASH_PWD" ]] && DASH_PWD="admin"

# =================下载与安装=================

# 获取最新版本
echo -e "${YELLOW}正在查询 GitHub 最新版本...${PLAIN}"
LATEST_VER=$(curl -s "https://api.github.com/repos/fatedier/frp/releases/latest" | jq -r .tag_name)

if [ -z "$LATEST_VER" ] || [ "$LATEST_VER" == "null" ]; then
    echo -e "${RED}获取版本失败，请输入版本号 (如 v0.60.0):${PLAIN}"
    read LATEST_VER
    if [ -z "$LATEST_VER" ]; then exit 1; fi
fi

VERSION_NO_V=${LATEST_VER#v}
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${LATEST_VER}/frp_${VERSION_NO_V}_linux_${ARCH}.tar.gz"
FILE_NAME="frp_${VERSION_NO_V}_linux_${ARCH}.tar.gz"
DIR_NAME="frp_${VERSION_NO_V}_linux_${ARCH}"

echo -e "${YELLOW}正在下载 frps ${LATEST_VER}...${PLAIN}"
curl -L -o "$FILE_NAME" "$DOWNLOAD_URL"

if [ ! -f "$FILE_NAME" ]; then
    echo -e "${RED}下载失败。${PLAIN}"
    exit 1
fi

echo -e "${YELLOW}正在安装...${PLAIN}"
tar -zxvf "$FILE_NAME"
cd "$DIR_NAME"

# 移动二进制文件
cp frps /usr/local/bin/
chmod +x /usr/local/bin/frps

# 创建配置目录
mkdir -p /etc/frp

# 生成配置文件 (frps.toml)
cat > /etc/frp/frps.toml <<EOF
# frps.toml - Created by install script
bindPort = $BIND_PORT

# 身份验证
auth.method = "token"
auth.token = "$AUTH_TOKEN"

# 仪表盘配置
webServer.addr = "0.0.0.0"
webServer.port = $DASH_PORT
webServer.user = "$DASH_USER"
webServer.password = "$DASH_PWD"

# 可选: 如果你需要 HTTP/HTTPS 穿透，取消下面注释并修改端口
# vhostHTTPPort = 8080
# vhostHTTPSPort = 8443
EOF

echo -e "${GREEN}配置文件已生成: /etc/frp/frps.toml${PLAIN}"

# 创建 Systemd 服务
cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=Frp Server Service
Documentation=https://github.com/fatedier/frp
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml

[Install]
WantedBy=multi-user.target
EOF

# 清理
cd ..
rm -rf "$DIR_NAME" "$FILE_NAME"

# 启动服务
systemctl daemon-reload
systemctl enable frps
systemctl restart frps

# =================显示结果=================
PUBLIC_IP=$(curl -s 4.ipw.cn || echo "你的服务器IP")

echo -e ""
echo -e "========================================"
echo -e "${GREEN}FRP 服务端安装成功！${PLAIN}"
echo -e "========================================"
echo -e " 服务状态 : $(systemctl is-active frps)"
echo -e " 绑定端口 : ${YELLOW}${BIND_PORT}${PLAIN}"
echo -e " Token    : ${GREEN}${AUTH_TOKEN}${PLAIN} (请妥善保存!)"
echo -e " 仪表盘   : http://${PUBLIC_IP}:${DASH_PORT}"
echo -e " 用户/密  : ${DASH_USER} / ${DASH_PWD}"
echo -e "========================================"
echo -e " 配置文件 : /etc/frp/frps.toml"
echo -e " 常用命令 : systemctl restart frps | systemctl status frps"
echo -e "========================================"
echo -e "${RED}注意：请确保防火墙已放行 TCP 端口 ${BIND_PORT} 和 ${DASH_PORT}${PLAIN}"
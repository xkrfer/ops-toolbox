#!/bin/bash

# ==================================================
# FRP Client (frpc) 快速安装脚本
# 支持架构: amd64, arm64
# 功能: 下载最新版, 配置 systemd 服务, 开机自启
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 权限运行此脚本。${PLAIN}" 
   echo -e "请使用: sudo bash $0"
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

# 获取最新版本号
echo -e "${YELLOW}正在查询 GitHub 最新版本...${PLAIN}"
# 如果在国内，GitHub API 可能会慢，如下载失败请考虑手动指定版本
LATEST_VER=$(curl -s "https://api.github.com/repos/fatedier/frp/releases/latest" | jq -r .tag_name)

if [ -z "$LATEST_VER" ] || [ "$LATEST_VER" == "null" ]; then
    echo -e "${RED}获取最新版本失败，可能是 GitHub API 限制或网络问题。${PLAIN}"
    read -p "请输入要安装的版本号 (例如 v0.60.0): " LATEST_VER
    if [ -z "$LATEST_VER" ]; then
        echo -e "${RED}版本号不能为空。${PLAIN}"
        exit 1
    fi
fi

# 去除版本号中的 'v' 前缀用于文件名
VERSION_NO_V=${LATEST_VER#v}

echo -e "检测到最新版本: ${GREEN}$LATEST_VER${PLAIN}"

# 构建下载链接
# 针对国内用户，如果下载慢，可以替换 GitHub Proxy，例如: https://mirror.ghproxy.com/
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${LATEST_VER}/frp_${VERSION_NO_V}_linux_${ARCH}.tar.gz"
FILE_NAME="frp_${VERSION_NO_V}_linux_${ARCH}.tar.gz"
DIR_NAME="frp_${VERSION_NO_V}_linux_${ARCH}"

echo -e "${YELLOW}正在下载 frpc...${PLAIN}"
echo -e "下载地址: $DOWNLOAD_URL"

curl -L -o "$FILE_NAME" "$DOWNLOAD_URL"

if [ ! -f "$FILE_NAME" ]; then
    echo -e "${RED}下载失败，请检查网络。${PLAIN}"
    exit 1
fi

# 解压和安装
echo -e "${YELLOW}正在安装...${PLAIN}"
tar -zxvf "$FILE_NAME"
cd "$DIR_NAME"

# 移动二进制文件
cp frpc /usr/local/bin/
chmod +x /usr/local/bin/frpc

# 创建配置目录
mkdir -p /etc/frp

# 创建默认配置文件 (TOML 格式，适配 FRP v0.52+)
if [ ! -f "/etc/frp/frpc.toml" ]; then
    cat > /etc/frp/frpc.toml <<EOF
# frpc.toml 示例配置
serverAddr = "127.0.0.1"
serverPort = 7000

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
EOF
    echo -e "${GREEN}已创建默认配置文件: /etc/frp/frpc.toml${PLAIN}"
else
    echo -e "${YELLOW}配置文件已存在，跳过覆盖。${PLAIN}"
fi

# 创建 Systemd 服务文件
cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=Frp Client Service
Documentation=https://github.com/fatedier/frp
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml

[Install]
WantedBy=multi-user.target
EOF

# 清理临时文件
cd ..
rm -rf "$DIR_NAME" "$FILE_NAME"

# 重新加载 Systemd 并启动
systemctl daemon-reload
systemctl enable frpc
systemctl start frpc

echo -e "------------------------------------------------"
echo -e "${GREEN}FRP 客户端安装完成！${PLAIN}"
echo -e "------------------------------------------------"
echo -e "配置文件路径: ${YELLOW}/etc/frp/frpc.toml${PLAIN}"
echo -e "查看状态命令: ${YELLOW}systemctl status frpc${PLAIN}"
echo -e "重启服务命令: ${YELLOW}systemctl restart frpc${PLAIN}"
echo -e "------------------------------------------------"
echo -e "请务必修改配置文件中的 serverAddr 为你的服务端 IP。"
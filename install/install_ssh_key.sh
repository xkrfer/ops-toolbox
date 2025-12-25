#!/bin/bash

# ==================================================
# SSH Key Installer (Optimized)
# 功能: 从 URL 下载公钥并安装到当前用户的 authorized_keys
# 支持架构: amd64, arm64
# 使用方式: ./install_ssh_key.sh [URL] [-p]
# 参数:
#   - URL: SSH 公钥下载地址
#   - -p: 禁用密码登录
# 示例:
#   ./install_ssh_key.sh https://example.com/ssh_key.pub -p 禁用密码登录
#   ./install_ssh_key.sh https://example.com/ssh_key.pub 
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 root 权限运行此脚本。${PLAIN}"
   exit 1
fi

# 初始化变量
SSH_KEY_URL=""
DISABLE_PW_LOGIN=0

# 参数解析
# 用法: ./script.sh [URL] [-p]
for arg in "$@"; do
    if [[ "$arg" == "-p" ]]; then
        DISABLE_PW_LOGIN=1
    elif [[ "$arg" =~ ^http.* ]]; then
        SSH_KEY_URL="$arg"
    fi
done

echo -e "Welcome to SSH Key Installer"

# 1. 获取密钥 URL (如果参数未提供，则询问)
if [[ -z "$SSH_KEY_URL" ]]; then
    echo -e "${YELLOW}请输入 SSH 公钥下载地址 (以 http/https 开头):${PLAIN}"
    read -r input_url
    if [[ -z "$input_url" ]]; then
        echo -e "${RED}错误: 地址不能为空。${PLAIN}"
        exit 1
    fi
    SSH_KEY_URL="$input_url"
fi

# 2. 准备 .ssh 目录和文件 (修复权限安全问题)
SSH_DIR="${HOME}/.ssh"
AUTH_FILE="${SSH_DIR}/authorized_keys"

if [ ! -d "$SSH_DIR" ]; then
    echo -e "创建目录: $SSH_DIR"
    mkdir -p "$SSH_DIR"
fi
# 关键: 设置目录权限 700
chmod 700 "$SSH_DIR"

if [ ! -f "$AUTH_FILE" ]; then
    echo -e "创建文件: $AUTH_FILE"
    touch "$AUTH_FILE"
fi
# 关键: 设置文件权限 600
chmod 600 "$AUTH_FILE"

# 3. 下载密钥
echo -e "${YELLOW}正在从 $SSH_KEY_URL 下载密钥...${PLAIN}"
TMP_KEY="/tmp/ssh_key_download.tmp"

# 使用 curl -f (失败不输出) -s (静默) -L (跟随重定向)
curl -fsSL "$SSH_KEY_URL" -o "$TMP_KEY"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}错误: 下载失败，请检查 URL 是否正确或网络连接。${PLAIN}"
    rm -f "$TMP_KEY"
    exit 1
fi

NEW_KEY=$(cat "$TMP_KEY")

# 简单校验内容是否像个 Key
if [[ "$NEW_KEY" != ssh-* ]]; then
    echo -e "${RED}错误: 下载的内容看起来不像 SSH 公钥。${PLAIN}"
    # 打印前20个字符供调试
    echo "内容预览: ${NEW_KEY:0:20}..."
    rm -f "$TMP_KEY"
    exit 1
fi

# 4. 检查是否已存在
# 使用 grep -F 固定字符串匹配，避免特殊字符干扰
if grep -Fq "$NEW_KEY" "$AUTH_FILE"; then
    echo -e "${YELLOW}警告: 该密钥已存在，跳过添加。${PLAIN}"
    rm -f "$TMP_KEY"
else
    echo -e "\n$NEW_KEY" >> "$AUTH_FILE"
    echo -e "${GREEN}密钥安装成功！${PLAIN}"
    rm -f "$TMP_KEY"
fi

# 5. 禁用密码登录 (如果选择了 -p)
if [[ $DISABLE_PW_LOGIN -eq 1 ]]; then
    CONFIG_FILE="/etc/ssh/sshd_config"
    echo -e "${YELLOW}正在禁用 SSH 密码登录...${PLAIN}"
    
    # 备份配置文件
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%F_%T)"
    
    # 修改 PasswordAuthentication
    if grep -q "^PasswordAuthentication" "$CONFIG_FILE"; then
        sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$CONFIG_FILE"
    else
        echo "PasswordAuthentication no" >> "$CONFIG_FILE"
    fi
    
    # 确保 PubkeyAuthentication 是 yes
    if grep -q "^PubkeyAuthentication" "$CONFIG_FILE"; then
        sed -i 's/^PubkeyAuthentication .*/PubkeyAuthentication yes/' "$CONFIG_FILE"
    else
        echo "PubkeyAuthentication yes" >> "$CONFIG_FILE"
    fi

    echo -e "${GREEN}配置已修改。${PLAIN}"
    
    # 尝试重启 SSH 服务
    if command -v systemctl &> /dev/null; then
        systemctl restart sshd || systemctl restart ssh
        echo -e "${GREEN}SSH 服务已重启。${PLAIN}"
    elif command -v service &> /dev/null; then
        service sshd restart || service ssh restart
        echo -e "${GREEN}SSH 服务已重启。${PLAIN}"
    else
        echo -e "${YELLOW}无法自动重启 SSH，请手动执行: service sshd restart${PLAIN}"
    fi
fi

echo -e "------------------------------------------------"
echo -e "完成。请在断开当前连接前，务必开启新窗口测试密钥连接！"
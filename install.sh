#!/bin/bash

# --- 配置区域 ---
# 请将下面的 URL 替换为你 GitHub 上编译好的二进制文件的 RAW 下载链接
DOWNLOAD_URL="https://github.com/xiaotianwm/socks5/raw/main/socks5-server"
INSTALL_PATH="/usr/local/bin/socks5-server"
SERVICE_NAME="mysocks5"

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (sudo bash install.sh ...)"
  exit 1
fi

# 检查参数
if [ "$#" -ne 3 ]; then
    echo "使用方法: bash install.sh <端口> <用户名> <密码>"
    echo "示例: bash install.sh 1080 myuser mypass123"
    exit 1
fi

PORT=$1
USER=$2
PASS=$3

echo "=== 开始安装 SOCKS5 服务 ==="

# 1. 停止旧服务（如果存在）
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "停止旧服务..."
    systemctl stop $SERVICE_NAME
    systemctl disable $SERVICE_NAME
fi

# 2. 下载二进制文件
echo "正在从 GitHub 下载..."
wget -O $INSTALL_PATH $DOWNLOAD_URL
if [ $? -ne 0 ]; then
    echo "下载失败，请检查 DOWNLOAD_URL 是否正确，或网络是否通畅。"
    exit 1
fi

# 3. 赋予执行权限
chmod +x $INSTALL_PATH
echo "下载完成，已赋予执行权限。"

# 4. 创建 Systemd 服务文件
echo "创建系统服务文件..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Simple SOCKS5 Server
After=network.target

[Service]
Type=simple
# 这里的参数由脚本传入
ExecStart=${INSTALL_PATH} -port ${PORT} -user ${USER} -pass ${PASS}
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 5. 重新加载并启动服务
echo "配置开机自启并启动服务..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# 6. 检查状态
sleep 2
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "=========================================="
    echo "✅ 安装成功！SOCKS5 服务已在后台运行。"
    echo "------------------------------------------"
    echo "端口: ${PORT}"
    echo "用户: ${USER}"
    echo "密码: ${PASS}"
    echo "------------------------------------------"
    echo "查看日志: journalctl -u ${SERVICE_NAME} -f"
    echo "停止服务: systemctl stop ${SERVICE_NAME}"
    echo "=========================================="
else
    echo "❌ 启动失败，请检查日志: systemctl status ${SERVICE_NAME}"
fi

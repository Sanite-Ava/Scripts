#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要以 root 权限运行。"
    echo "请尝试使用 'sudo bash $0' 或切换到 root 用户后运行。"
    exit 1
fi

set -e

echo "正在更新软件包列表并安装必要工具 (curl, openssl, qrencode)..."
apt-get update -y > /dev/null
apt-get install -y curl openssl qrencode> /dev/null

echo "正在检查并安装/更新 Xray-core..."
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

SERVER_IPV4=$(curl -s -m 5 ipv4.ip.sb)
SERVER_IPV6=$(curl -s -m 5 ipv6.ip.sb)

if [ -z "$SERVER_IPV4" ] && [ -z "$SERVER_IPV6" ]; then
    echo "错误: 无法获取服务器的任何公网 IP 地址。脚本终止。"
    exit 1
fi

XRAY_UUID=$(xray uuid)
X25519_KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$X25519_KEYS" | awk '/Private key/ {print $3}')
PUBLIC_KEY=$(echo "$X25519_KEYS" | awk '/Public key/ {print $3}')
SHORT_ID=$(openssl rand -hex 8)
SS_PASSWORD=$(openssl rand -base64 16)

clear
echo "=========================================="
echo "          Xray 安装与配置脚本"
echo "=========================================="
echo ""
echo "请选择要应用的 Xray 配置模板:"
echo ""
echo "  1) VLESS Reality Vision (推荐)"
echo "  2) Shadowsocks 2022"
echo "  3) 退出脚本"
echo ""
read -p "请输入您的选项 [1-3]: " choice

case "$choice" in
    1)
        echo "正在配置 VLESS Reality Vision..."
        CONFIG_TYPE="VLESS Reality Vision"
        cat > /usr/local/etc/xray/config.json << EOF
{
    "inbounds": [
        {
            "tag": "dokodemo-in",
            "port": 443,
            "protocol": "dokodemo-door",
            "settings": {
                "address": "127.0.0.1",
                "port": 4431,
                "network": "tcp"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "tls"
                ],
                "routeOnly": true
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 4431,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${XRAY_UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "speed.cloudflare.com:443",
                    "serverNames": [
                        "speed.cloudflare.com"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "",
                        "${SHORT_ID}"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "routeOnly": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing": {
        "rules": [
            {
                "inboundTag": [
                    "dokodemo-in"
                ],
                "domain": [
                    "speed.cloudflare.com"
                ],
                "outboundTag": "direct"
            },
            {
                "inboundTag": [
                    "dokodemo-in"
                ],
                "outboundTag": "block"
            }
        ]
    }
}
EOF
        ;;
    2)
        echo "正在配置 Shadowsocks 2022..."
        CONFIG_TYPE="Shadowsocks 2022"
        cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "port": 65535,
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "${SS_PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
        ;;
    3)
        echo "已选择退出，脚本结束。"
        exit 0
        ;;
    *)
        echo "无效的选项。脚本退出。"
        exit 1
        ;;
esac

echo "正在启用并重启 Xray 服务..."
systemctl enable xray > /dev/null
systemctl restart xray

echo "等待服务启动..."
sleep 2

if systemctl is-active --quiet xray; then
    echo "✔ Xray 服务已成功启动！"
else
    echo "❌ 错误: Xray 服务启动失败！"
    echo "请立即使用以下命令查看日志以排查问题:"
    echo "journalctl -u xray -n 50 --no-pager"
    exit 1
fi

clear
echo "🎉 恭喜！Xray 已成功配置 🎉"
echo "=================================================="
echo "您的配置类型: $CONFIG_TYPE"
echo "--------------------------------------------------"

if [ "$choice" -eq 1 ]; then
    NODE_NAME="VLESS_Reality_Vision"
    SERVER_IP_FOR_LINK=${SERVER_IPV4:-$SERVER_IPV6}
    VLESS_LINK="vless://${XRAY_UUID}@${SERVER_IP_FOR_LINK}:443?type=tcp&security=reality&flow=xtls-rprx-vision&sni=speed.cloudflare.com&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#${NODE_NAME}"
 
    echo "请手动配置或使用以下链接/二维码导入:"
    echo ""
    echo "   服务器地址: ${SERVER_IPV4} | ${SERVER_IPV6}"
    echo "   端口: 443"
    echo "   UUID: ${XRAY_UUID}"
    echo "   公钥 (PublicKey): ${PUBLIC_KEY}"
    echo "   Short ID: ${SHORT_ID}"
    echo "   SNI (Server Name): www.microsoft.com"
    echo "   安全协议: reality"
    echo "   Flow: xtls-rprx-vision"
    echo ""
    echo "⬇️ 导入链接 (vless): "
    echo ""
    echo "${VLESS_LINK}"
    echo ""
    echo "⬇️ 扫描二维码导入:"
    echo ""
    qrencode -t ANSIUTF8 "${VLESS_LINK}"
    echo ""

elif [ "$choice" -eq 2 ]; then
    NODE_NAME="Shadowsocks_2022"
    SERVER_IP_FOR_LINK=${SERVER_IPV4:-$SERVER_IPV6}
    SS_PAYLOAD_B64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${SS_PAYLOAD_B64}@${SERVER_IP_FOR_LINK}:65535#${NODE_NAME}"
 
    echo "请手动配置或使用以下链接/二维码导入:"
    echo ""
    echo "   服务器地址: ${SERVER_IPV4} | ${SERVER_IPV6}"
    echo "   端口: 65535"
    echo "   密码: ${SS_PASSWORD}"
    echo "   加密方法: 2022-blake3-aes-128-gcm"
    echo ""
    echo "⬇️ 导入链接 (ss): "
    echo ""
    echo "${SS_LINK}"
    echo ""
    echo "⬇️ 扫描二维码导入:"
    echo ""
    qrencode -t ANSIUTF8 "${SS_LINK}"
    echo ""
fi

echo "=================================================="
echo "提示: 您的 SSH 客户端窗口大小可能会影响二维码显示。"
echo "如果二维码显示不全，请尝试调小字体或放大窗口。"
echo "您也可以使用 'journalctl -u xray -f' 命令实时监控 Xray 日志。"
echo ""
 
exit 0
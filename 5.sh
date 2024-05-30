#!/bin/sh

echo "请输入socks端口:"
read socks_port

# 清空iptables规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X
iptables-save

# 获取本机IP地址列表
ips=($(hostname -I))

# Xray安装与设置
wget -O /usr/local/bin/xray.zip https://github.com/qza666/socks5/raw/main/Xray-linux-64.zip
unzip /usr/local/bin/xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/xray

# 创建systemd服务文件
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=The Xray Proxy Serve
After=network-online.target

[Service]
ExecStart=/usr/local/bin/xray -c /etc/xray/serve.toml
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=always
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOF

# 启用并重新加载systemd守护进程
systemctl daemon-reload
systemctl enable xray

# 创建配置目录和文件
mkdir -p /etc/xray
echo -n "" > /etc/xray/serve.toml
for ((i = 0; i < ${#ips[@]}; i++)); do
    cat <<EOF >> /etc/xray/serve.toml
[[inbounds]]
listen = "${ips[i]}"
port = $socks_port
protocol = "socks"
tag = "$((i+1))"

[inbounds.settings]
auth = "noauth"
udp = true
ip = "${ips[i]}"

[[routing.rules]]
type = "field"
inboundTag = "$((i+1))"
outboundTag = "$((i+1))"

[[outbounds]]
sendThrough = "${ips[i]}"
protocol = "freedom"
tag = "$((i+1))"
EOF
done

# 设置并重新加载防火墙
firewall-cmd --zone=public --add-port=$socks_port/tcp --add-port=$socks_port/udp --permanent
firewall-cmd --reload

# 停止并启动Xray服务
systemctl stop xray
systemctl start xray

# 显示本机所有IP地址并保存到文件
filename=$(hostname -I | awk '{print $1}').txt
echo "$(date '+%Y-%m-%d')" > $filename
hostname -I | tr ' ' '\n' >> $filename 

# 重启xray服务
systemctl restart xray

# 删除安装脚本
cleanup() {
  rm -f /root/socks51.sh
}
trap cleanup EXIT

# 显示完成信息
echo "====================================="
echo "==>已安装完毕，赶紧去测试一下!"
echo "====================================="

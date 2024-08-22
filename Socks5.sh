#!/bin/bash

set -euo pipefail

# 定义颜色和日志函数
declare -r GREEN='\033[0;32m'
declare -r RED='\033[0;31m'
declare -r NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }

DEFAULT_START_PORT=20000

declare -A last_seen
declare -A port_to_ipv6
timeout=600  # 超时时间，单位秒

setup_environment() {
    check_command curl

    chmod 777 /root/socks5.sh

    ipv6_prefix=$(ip -6 addr show | awk '/inet6/ && !/::1/ {print $2; exit}' | cut -d':' -f1-4)
    [[ -z "$ipv6_prefix" ]] && { log_error "无法获取IPv6前缀"; exit 1; }
    log_info "获取到的IPv6前缀为: ${ipv6_prefix}"
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || { log_error "$1 未安装。中止。"; exit 1; }
}

read_input_with_default() {
    local prompt="$1"
    local default_value="$2"
    read -p "$prompt [默认: $default_value]: " input_value
    echo "${input_value:-$default_value}"
}

create_config() {
    local -r config_file="/root/socks5_config.cfg"
    local number dynamic ip_pool time

    number=$(read_input_with_default "需要搭建多少个代理" "500")
    dynamic=$(read_input_with_default "是否搭建动态代理 (true/false)" "false")
    ip_pool="$number"
    time="99999"

    [[ "$dynamic" = "true" ]] && {
        ip_pool=$(read_input_with_default "请输入ip池的数量" "10000")
        time=$(read_input_with_default "IP轮换时间 (分钟)" "5")
    }

    cat > "$config_file" <<EOF
ipv6_prefix=$ipv6_prefix
number=$number
dynamic=$dynamic
ip_pool=$ip_pool
time=$time
EOF

    log_info "配置文件已创建"
}

configure_ipv6() {
    source "/root/socks5_config.cfg"
    
    ip -6 addr show scope global | awk '/inet6/ {print $2}' | xargs -r -I {} ip -6 addr del {} dev eth0

    for _ in $(seq 1 "$number"); do
        new_ipv6="${ipv6_prefix}:$(printf '%04x:%04x:%04x:%04x' $((RANDOM%0xffff)) $((RANDOM%0xffff)) $((RANDOM%0xffff)) $((RANDOM%0xffff)))/48"
        ip -6 addr add "$new_ipv6" dev eth0 && log_info "成功应用IPv6地址：$new_ipv6" || log_error "应用IPv6地址失败：$new_ipv6"
    done
}

install_xray() {
    log_info "开始安装 Xray..."
    apt-get update
    apt-get install -y unzip
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL
    cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=root
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xrayL.service
    log_info "Xray 安装完成"
}

config_xray() {
    log_info "开始配置 Xray..."
    source "/root/socks5_config.cfg"
    IP_ADDRESSES=($(hostname -I))  # 获取所有IP地址
    mkdir -p /etc/xrayL
    START_PORT=${DEFAULT_START_PORT}
    config_content=""
    
    local ip_count=${#IP_ADDRESSES[@]}
    local ports_per_ip=$((number / ip_count))
    local remaining_ports=$((number % ip_count))
    
    local current_port=$START_PORT
    for ((i = 0; i < ip_count; i++)); do
        local ports_for_this_ip=$ports_per_ip
        if [ $i -lt $remaining_ports ]; then
            ports_for_this_ip=$((ports_for_this_ip + 1))
        fi
        
        for ((j = 0; j < ports_for_this_ip; j++)); do
            config_content+="[[inbounds]]\nport = $current_port\nprotocol = \"socks\"\ntag = \"tag_$current_port\"\n[inbounds.settings]\nauth = \"noauth\"\nudp = true\nip = \"${IP_ADDRESSES[i]}\"\n[[outbounds]]\nsendThrough = \"${IP_ADDRESSES[i]}\"\nprotocol = \"freedom\"\ntag = \"tag_$current_port\"\n[[routing.rules]]\ntype = \"field\"\ninboundTag = \"tag_$current_port\"\noutboundTag = \"tag_$current_port\"\n\n"
            current_port=$((current_port + 1))
        done
    done
    
    echo -e "$config_content" >/etc/xrayL/config.toml
    systemctl restart xrayL.service
    log_info "Xray 配置完成，使用了 ${#IP_ADDRESSES[@]} 个IP地址"
}

check_xray_status() {
    status=$(systemctl is-active xrayL.service)
    if [ "$status" == "active" ]; then
        log_info "Xray 服务运行状态: $status"
    else
        log_error "Xray 服务运行状态: $status"
        log_info "服务未成功启动，重新安装和配置..."
        install_xray
        config_xray
        systemctl restart xrayL.service
        check_xray_status
    fi
}

setup_socks() {
    [ -x "$(command -v xrayL)" ] || install_xray
    config_xray
    check_xray_status
}

check_proxy() {
    local host="$1"
    local port="$2"

    response=$(curl -s -m 5 --socks5-hostname "$host:$port" "https://api64.ipify.org")
    if [[ $? -eq 0 ]]; then
        if ! grep -q "$response" /root/socks5_ipv6.txt; then
            echo "$response" >> /root/socks5_ipv6.txt
            echo "代理: $host:$port, 正确, 返回值: $response"
        else
            echo "代理: $host:$port, 正确, 返回值: $response 已存在"
        fi
    else
        echo "代理: $host:$port, 错误, 返回值: $response"
    fi
}

export -f check_proxy

check_proxies() {
    local host=$(hostname -I | awk '{print $1}')
    local start_port=$DEFAULT_START_PORT
    local end_port=$((start_port + number))

    seq $start_port $end_port | parallel -j 50 check_proxy $host {}
}

detection() {
    source "/root/socks5_config.cfg"
    
    while true; do
        log_info "开始检测代理..."
        
        check_proxies
        
        local count=$(wc -l < /root/socks5_ipv6.txt)
        log_info "当前文本内的IP数量: $count"
        
        if [[ "$count" -lt "$ip_pool" ]]; then
            log_info "检测到的可用代理数量($count)少于配置数量($ip_pool)，重新配置IPv6和代理..."
            configure_ipv6
            setup_socks
        else
            log_info "已经满足账号池，当前IP池数量：$count"
            break
        fi
    done
    log_info "准备执行 xray 函数..."
    xray
    log_info "xray 函数执行完成"
}

setup_dynamic_proxy() {
    log_info "设置动态代理..."
    # 设置80端口监听
    cat > /root/http_server.py <<EOF
# -*- coding: utf-8 -*-
import http.server
import socketserver
import subprocess
import os

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write("刷新成功".encode('utf-8'))
        subprocess.run(["/bin/bash", "-c", "source /root/socks5.sh && xray"])

if __name__ == "__main__":
    os.chdir('/root')
    with socketserver.TCPServer(("", 80), MyHandler) as httpd:
        print("正在监控 80端口.....")
        httpd.serve_forever()
EOF

    # 启动HTTP服务器
    nohup python3 /root/http_server.py > /dev/null 2>&1 &

    # 设置定时任务
    (crontab -l 2>/dev/null; echo "0 * * * * /bin/bash /root/socks5.sh xray") | crontab -
    log_info "动态代理设置完成"

    sed -i 's/^dynamic=.*$/dynamic=null/' /root/socks5_config.cfg
}

# 随机读取配置文件中指定数量的唯一IPv6地址
read_random_ipv6() {
    source "/root/socks5_config.cfg"
    head -n 10 /root/socks5_ipv6.txt
    shuf /root/socks5_ipv6.txt | awk '!seen[$0]++' | head -n "$number"
}

# 应用IPv6地址的函数
apply_ipv6() {
  local ipv6="$1"
  if ip -6 addr add "$ipv6" dev eth0; then
    echo "成功应用IPv6地址：$ipv6"
  else
    echo "应用IPv6地址失败：$ipv6"
  fi
}

xray() {
    source "/root/socks5_config.cfg"

    echo "开始清空ipv6的应用"
    ip -6 addr show scope global | awk '/inet6/ {print $2}' | xargs -r -I {} ip -6 addr del {} dev eth0

    # 应用随机选取的配置文件中指定数量的IPv6地址
    while IFS= read -r ipv6; do
        apply_ipv6 "$ipv6"
    done < <(read_random_ipv6)

    setup_socks

    if [[ "$dynamic" == "true" ]]; then
        setup_dynamic_proxy
    fi

    echo "清空ipv6并调用监控函数"
    ip -6 addr show scope global | awk '/inet6/ {print $2}' | xargs -r -I {} ip -6 addr del {} dev eth0
    
    # 调用监控函数

    cat > /root/port_monitor.py <<EOF
# -*- coding: utf-8 -*-
import subprocess
import re
import threading
import toml
from datetime import datetime, timedelta

# 全局变量，存储端口与IP的映射
port_ip_map = {}
# 记录最后访问时间
last_accessed = {}
# 已应用的IP集合
applied_ips = {}

# 缓冲队列
buffered_ports = set()

# 解析配置文件
def parse_config():
    with open('/etc/xrayL/config.toml', 'r') as file:
        config = toml.load(file)
        for inbound in config['inbounds']:
            port = int(inbound['port'])
            port_ip_map[port] = inbound['settings']['ip']

# 检查IP是否已经应用
def is_ip_applied(ip):
    result = subprocess.run(['ip', 'addr', 'show', 'dev', 'eth0'], capture_output=True, text=True)
    return ip in result.stdout

# 应用IP
def apply_ip(ip):
    if not is_ip_applied(ip):
        subprocess.run(['ip', 'addr', 'add', f'{ip}/48', 'dev', 'eth0'], check=True)
        applied_ips[ip] = datetime.now()

# 取消应用IP
def remove_ip(ip):
    if is_ip_applied(ip):
        subprocess.run(['ip', 'addr', 'del', f'{ip}/48', 'dev', 'eth0'], check=True)
        if ip in applied_ips:
            del applied_ips[ip]

# 更新IP状态
def update_ip_statuses():
    now = datetime.now()
    for ip, last_used in list(applied_ips.items()):
        if now - last_used > timedelta(minutes=10):
            remove_ip(ip)

# 处理缓冲队列
def process_buffer():
    while True:
        if buffered_ports:
            port = buffered_ports.pop()
            ip = port_ip_map.get(port)
            if ip:
                apply_ip(ip)
                update_ip_statuses()

# 使用tcpdump监控端口
def monitor_traffic():
    start_port = 20001
    end_port = 29999
    command = f"sudo tcpdump -i any 'dst portrange {start_port}-{end_port}' -nn -q -l"
    process = subprocess.Popen(command, shell=True, text=True, stdout=subprocess.PIPE)

    while True:
        line = process.stdout.readline()
        if line:
            port_search = re.search(r'IP \S+ > \S+\.(\d+):', line)
            if port_search:
                port = int(port_search.group(1))
                if port in port_ip_map:
                    last_accessed[port] = datetime.now()
                    buffered_ports.add(port)  # 将端口添加到缓冲队列

# 主函数
def main():
    parse_config()
    threading.Thread(target=process_buffer, daemon=True).start()
    monitor_traffic()

if __name__ == "__main__":
    main()

EOF

    nohup python3 /root/port_monitor.py > /var/log/port_monitor.log 2>&1 &
    #python3 /root/port_monitor.py
}

main() {
    setup_environment
    [[ -f "/root/socks5_config.cfg" ]] || create_config
    configure_ipv6
    setup_socks
    detection
}

# 允许直接调用函数
if [[ "${1:-}" ]]; then
    "$@"
else
    main
fi

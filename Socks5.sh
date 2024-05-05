#!/bin/bash

# 函数，用于检测操作系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
    else
        OS=$(uname -s)
    fi
    echo "检测到的操作系统: $OS"
}

# 函数，用于执行选定的脚本
run_script() {
    case $1 in
        1)
            echo "在 Ubuntu 上运行带密码的 Socks5 版本..."
            bash <(curl -Ls https://raw.githubusercontent.com/kangcwei/ss5/main/ss5i.sh)
            ;;
        2)
            echo "在 Ubuntu 上运行免密码的 Socks5 版本..."
            bash <(curl -Ls https://raw.githubusercontent.com/qza666/socks5/main/socks5)
            ;;
        3)
            echo "在 CentOS 上运行多 IP 带密码版本..."
            yum install -y wget && wget -O 4.sh https://raw.githubusercontent.com/qza666/socks5/main/4.sh && sh 4.sh && rm 4.sh
            ;;
        4)
            echo "在 CentOS 上运行多 IP 免密码版本..."
            yum install -y wget && wget -O 5.sh https://raw.githubusercontent.com/qza666/socks5/main/5.sh && sh 5.sh && rm 5.sh
            ;;
        5)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo "无效选项。请输入 1 到 5 之间的数字。"
            ;;
    esac
}

# 主脚本
detect_os

echo "请选择要运行的安装脚本："
echo "1: Ubuntu 上的带密码 Socks5 版本"
echo "2: Ubuntu 上的免密码 Socks5 版本"
echo "3: CentOS 上的多 IP 带密码版本"
echo "4: CentOS 上的多 IP 免密码版本"
echo "5: 退出脚本"
read -p "输入您的选择（1-5）: " user_choice

run_script $user_choice

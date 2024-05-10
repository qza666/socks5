#!/bin/bash

# 定义一个包含每个节点 refreshCookie 的数组
refreshCookies=("cookie1" "cookie2" "cookie3" "cookie4" "cookie5" "cookie6" "cookie7" "cookie8" "cookie9")

while true
do
    for node_id in {1..9}
    do
        # 从数组中获取对应节点的 refreshCookie
        refreshCookie=${refreshCookies[$node_id - 1]}

        # 定义节点路径
        node_path="/root/SoruxNode/chat-$node_id"
        cd $node_path
        
        # 删除 session.json 文件
        rm -f config/session.json

        # 停止并移除容器
        docker-compose stop
        docker-compose rm -f

        # 创建新的 session.json 文件
        cat > config/session.json << EOF
{
  "refreshCookie": "$refreshCookie"
}
EOF

        # 启动容器
        docker-compose up -d
    done

    # 等待5分钟
    sleep 300
done

#!/bin/bash

PROXY_PORT=1080
PID_FILE="/tmp/git_proxy_ssh.pid"

function start_proxy() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            echo "⚠️ 检测到代理已在运行 (PID=$PID)，跳过重复配置。"
            return
        fi
    fi

    CONFIG_FILE=~/.gitproxy_config
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    read -p "🔧 请输入 Azure 服务器 IP 地址 [默认: $CACHED_IP]: " AZURE_IP
    AZURE_IP=${AZURE_IP:-$CACHED_IP}

    read -p "👤 请输入登录用户名 [默认: $CACHED_USER]: " AZURE_USER
    AZURE_USER=${AZURE_USER:-$CACHED_USER}

    echo "🔐 请选择登录方式："
    echo "  1. 使用私钥"
    echo "  2. 使用密码"
    read -p "请输入 1 或 2 [默认: ${CACHED_LOGIN_METHOD:-1}]: " LOGIN_METHOD
    LOGIN_METHOD=${LOGIN_METHOD:-${CACHED_LOGIN_METHOD:-1}}

    if [ "$LOGIN_METHOD" == "1" ]; then
        read -e -p "🗝️ 请输入私钥路径 [默认: $CACHED_KEY_PATH 或 ~/.ssh/id_rsa]: " KEY_PATH
        KEY_PATH=${KEY_PATH:-$CACHED_KEY_PATH}
        KEY_PATH=${KEY_PATH:-~/.ssh/id_rsa}
        echo "🔌 正在使用私钥建立 SSH SOCKS5 代理..."
        ssh -i "$KEY_PATH" -N -D $PROXY_PORT "$AZURE_USER@$AZURE_IP" &
    elif [ "$LOGIN_METHOD" == "2" ]; then
        echo "🔑 输入登录密码（会提示密码）..."
        ssh -N -D $PROXY_PORT "$AZURE_USER@$AZURE_IP" &
    else
        echo "❌ 无效的选项，退出。"
        exit 1
    fi

    SSH_PID=$!
    echo $SSH_PID > "$PID_FILE"
    echo "✅ SSH 隧道已建立，PID=$SSH_PID"

    echo "🧩 设置 Git 代理配置..."
    git config --global http.proxy "socks5h://127.0.0.1:$PROXY_PORT"
    git config --global https.proxy "socks5h://127.0.0.1:$PROXY_PORT"
    echo "✅ Git 代理设置完成！"

    cat > "$CONFIG_FILE" << EOF
CACHED_IP=$AZURE_IP
CACHED_USER=$AZURE_USER
CACHED_KEY_PATH=$KEY_PATH
CACHED_LOGIN_METHOD=$LOGIN_METHOD
EOF
    echo "💾 配置已保存到 $CONFIG_FILE"
}

function stop_proxy() {
    echo "🛑 正在关闭 Git 代理..."
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    echo "✅ Git 代理配置已清除"

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            kill "$PID"
            echo "🔪 已杀掉 SSH 进程 (PID=$PID)"
        fi
        rm -f "$PID_FILE"
    else
        echo "⚠️ 没有找到运行中的 SSH 代理记录"
    fi
}

function status_proxy() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            echo "🟢 代理正在运行中 (PID=$PID)"
        else
            echo "🔴 PID 文件存在但进程已结束"
        fi
    else
        echo "🔴 没有运行中的代理"
    fi
}

function test_speed() {
    echo "🚀 正在测试 GitHub 拉取速度..."
    TEMP_DIR=$(mktemp -d)
    REPO_URL="https://github.com/githubtraining/hellogitworld.git"

    START_TIME=$(date +%s)
    git clone --depth=1 "$REPO_URL" "$TEMP_DIR/test-repo" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 克隆失败，请确认代理是否正确连接"
        rm -rf "$TEMP_DIR"
        return
    fi
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "✅ 拉取完成，用时 $DURATION 秒"
    rm -rf "$TEMP_DIR"
}

case "$1" in
    start)
        start_proxy
        ;;
    stop)
        stop_proxy
        ;;
    status)
        status_proxy
        ;;
    test)
        test_speed
        ;;
    reset)
        echo "🧹 正在清除配置缓存..."
        CONFIG_FILE=~/.gitproxy_config
        if [ -f "$CONFIG_FILE" ]; then
            rm "$CONFIG_FILE"
            echo "✅ 已删除配置：$CONFIG_FILE"
        else
            echo "ℹ️ 未检测到配置文件"
        fi
        ;;
    uninstall)
        echo "🧨 正在卸载 gitproxy..."

        CONFIG_FILE=~/.gitproxy_config
        SCRIPT_PATH="$0"

        rm -f "$CONFIG_FILE" && echo "🧹 已删除配置文件 $CONFIG_FILE"
        sed -i '/alias gitproxy=.*/d' ~/.bashrc 2>/dev/null
        sed -i '/alias gitproxy=.*/d' ~/.zshrc 2>/dev/null
        echo "🧼 已从 shell 配置中移除 alias"

        rm -f "$SCRIPT_PATH" && echo "🗑️ 已删除脚本 $SCRIPT_PATH"

        source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null
        echo "✅ gitproxy 卸载完成！"
        exit 0
        ;;
    help|--help)
        echo ""
        echo "📘 gitproxy 命令列表："
        echo "  gitproxy start      # 启动 SOCKS5 代理并设置 Git 代理"
        echo "  gitproxy stop       # 停止代理并清除 Git 配置"
        echo "  gitproxy status     # 查看代理运行状态"
        echo "  gitproxy test       # 测试 GitHub 克隆速度"
        echo "  gitproxy reset      # 清除保存的连接配置"
        echo "  gitproxy uninstall  # 卸载 gitproxy 并清理所有内容"
        echo "  gitproxy help       # 查看命令说明"
        echo ""
        ;;
    *)
        echo "❓ 未知命令：$1"
        echo "👉 输入 'gitproxy help' 查看可用命令"
        ;;
esac
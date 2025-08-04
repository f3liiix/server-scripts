#!/bin/bash

# ==============================================================================
# Script Name: install-online.sh
# Description: 服务器优化工具集合在线安装脚本 (简化版)
# Usage:       bash <(curl -sL https://your-domain.com/install.sh)
# ==============================================================================

set -euo pipefail

# --- 配置项 ---
readonly VERSION="1.0"
readonly REPO_URL="https://github.com/your-username/server-scripts"
readonly RAW_BASE="https://ss.hide.ss"
readonly INSTALL_DIR="/opt/server-optimization"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 日志函数
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "需要root权限运行此脚本"
        echo "请使用: sudo bash <(curl -sL your-install-url)"
        exit 1
    fi
}

# 快速系统检查
check_system() {
    log "检查系统环境..."
    
    # 检查基本命令
    for cmd in curl wget git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "建议安装 $cmd 以获得更好体验"
        fi
    done
    
    # 检测系统类型
    if [[ -f /etc/debian_version ]]; then
        success "检测到 Debian/Ubuntu 系统"
    elif [[ -f /etc/redhat-release ]]; then
        success "检测到 RedHat/CentOS 系统"
    else
        warn "未知系统类型，继续安装..."
    fi
}

# 下载并安装
install_tools() {
    log "开始下载和安装服务器优化工具..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # 下载主要脚本文件
    local files=(
        "scripts/common_functions.sh"
        "scripts/run_optimization.sh"
        "scripts/disable_ipv6.sh"
        "scripts/tcp_tuning.sh"
        "scripts/enable_bbr.sh"
        "scripts/configure_ssh.sh"
        "scripts/configure_dns.sh"
        "install.sh"
    )
    
    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        mkdir -p "$dir"
        
        log "下载: $file"
        if curl -fsSL "$RAW_BASE/$file" -o "$file"; then
            success "✅ $file"
        else
            error "❌ 下载失败: $file"
            exit 1
        fi
    done
    
    # 设置权限
    find . -name "*.sh" -exec chmod +x {} \;
    chown -R root:root "$INSTALL_DIR"
    
    success "文件下载完成"
}

# 创建全局命令
create_commands() {
    log "创建全局命令..."
    
    local main_script="$INSTALL_DIR/scripts/run_optimization.sh"
    
    # 创建主命令
    cat > /usr/local/bin/server-optimize << EOF
#!/bin/bash
exec $main_script "\$@"
EOF
    
    # 创建快捷命令
    for func in ipv6 tcp bbr ssh dns; do
        cat > "/usr/local/bin/optimize-$func" << EOF
#!/bin/bash
exec $main_script $func "\$@"
EOF
    done
    
    chmod +x /usr/local/bin/server-optimize /usr/local/bin/optimize-*
    success "全局命令创建完成"
}

# 显示使用说明
show_usage() {
    echo
    echo -e "${GREEN}🎉 服务器优化工具安装完成！${NC}"
    echo
    echo -e "${CYAN}快速使用:${NC}"
    echo "  server-optimize --help    # 查看帮助"
    echo "  server-optimize tcp       # TCP网络优化"
    echo "  server-optimize dns       # DNS服务器配置"
    echo "  server-optimize bbr       # 启用BBR算法"
    echo "  server-optimize ssh       # SSH安全配置"
    echo "  server-optimize all       # 运行所有优化"
    echo
    echo -e "${CYAN}快捷命令:${NC}"
    echo "  optimize-tcp              # 直接运行TCP优化"
    echo "  optimize-dns              # 直接运行DNS配置"
    echo "  optimize-bbr              # 直接启用BBR"
    echo
    echo -e "${YELLOW}现在开始优化您的服务器吧！${NC}"
    echo
}

# 交互式选择
interactive_setup() {
    echo -e "${CYAN}是否立即运行优化？${NC}"
    echo "1) TCP网络优化 (推荐)"
    echo "2) DNS服务器配置"
    echo "3) 全部优化"
    echo "4) 稍后手动运行"
    echo
    
    read -p "选择 (1-4): " choice
    
    case $choice in
        1) server-optimize tcp ;;
        2) server-optimize dns ;;
        3) server-optimize all ;;
        *) log "您可以稍后运行 server-optimize --help 查看使用方法" ;;
    esac
}

# 主程序
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          服务器优化工具集合 - 一键安装脚本 v$VERSION          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    check_system
    install_tools
    create_commands
    show_usage
    
    # 如果不是通过参数 --install-only 调用，则显示交互选项
    if [[ "${1:-}" != "--install-only" ]]; then
        interactive_setup
    fi
}

# 执行主程序
main "$@"
#!/bin/bash

# ==============================================================================
# Script Name: install.sh
# Description: 服务器优化工具集合在线脚本
# Usage:       bash <(curl -sL ss.hide.ss)
# ==============================================================================

set -euo pipefail

# --- 配置项 ---
readonly VERSION="1.0.0"
readonly REPO_URL="https://github.com/f3liiix/server-scripts"
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
        error "需要 root 权限运行此脚本"
        echo "请使用: sudo bash <(curl -sL ss.hide.ss)"
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
    )
    
    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        mkdir -p "$dir"
        
        # 静默下载，只在失败时输出错误
        if ! curl -fsSL "$RAW_BASE/$file" -o "$file" 2>/dev/null; then
            error "❌ 下载失败: $file"
            exit 1
        fi
    done
    
    # 设置权限
    find . -name "*.sh" -exec chmod +x {} \;
    chown -R root:root "$INSTALL_DIR" 2>/dev/null || true
}

# 验证安装
verify_installation() {
    # 验证主控制脚本是否存在且可执行
    local main_script="$INSTALL_DIR/scripts/run_optimization.sh"
    
    if [[ -f "$main_script" ]] && [[ -x "$main_script" ]]; then
        return 0
    else
        return 1
    fi
}

# 显示菜单说明
show_menu_info() {
    echo
    echo -e "${GREEN}🎉 服务器优化工具已就绪！${NC}"
    echo -e "${CYAN}💡 提示：选择对应数字即可运行优化项目${NC}"
    echo
}

# 系统初始化（下载和验证）
initialize_system() {
    log "正在初始化脚本..."
    
    # 开始进度显示
    printf "${BLUE}[INFO]${NC} 初始化进度: "
    
    # 执行下载
    install_tools
    printf "▓▓"
    
    # 验证安装
    if verify_installation; then
        printf "▓ ✅\n"
        success "初始化完成"
    else
        printf "▓ ❌\n"
        error "初始化失败"
        exit 1
    fi
}

# 运行优化脚本
run_optimization() {
    local option="$1"
    local main_script="$INSTALL_DIR/scripts/run_optimization.sh"
    
    if [[ -x "$main_script" ]]; then
        "$main_script" "$option"
    else
        error "优化脚本未找到或无执行权限"
        exit 1
    fi
}

# 交互式菜单
interactive_menu() {
    while true; do
        echo
        echo -e "${CYAN}请选择要执行的优化项目：${NC}"
        echo
        echo "  1) TCP网络调优          # 推荐 - 提升网络性能"
        echo "  2) DNS服务器配置        # 推荐 - 提升解析速度"
        echo "  3) 一键开启BBR          # 高延迟网络优化"
        echo "  4) SSH安全配置          # 端口和密码设置"
        echo "  5) 禁用IPv6             # 避免双栈网络问题"
        echo "  6) 全部优化             # 运行所有优化项目"
        echo "  0) 退出程序"
        echo
        
        read -p "$(echo -e "${YELLOW}请输入选择 (0-6): ${NC}")" choice
        
        case $choice in
            1)
                echo -e "${GREEN}开始 TCP网络调优...${NC}"
                run_optimization "tcp"
                ;;
            2)
                echo -e "${GREEN}开始 DNS服务器配置...${NC}"
                run_optimization "dns"
                ;;
            3)
                echo -e "${GREEN}开始 一键开启BBR...${NC}"
                run_optimization "bbr"
                ;;
            4)
                echo -e "${GREEN}开始 SSH安全配置...${NC}"
                run_optimization "ssh"
                ;;
            5)
                echo -e "${GREEN}开始 禁用IPv6...${NC}"
                run_optimization "ipv6"
                ;;
            6)
                echo -e "${GREEN}开始全部优化...${NC}"
                run_optimization "all"
                ;;
            0)
                echo -e "${YELLOW}感谢使用服务器优化工具！${NC}"
                exit 0
                ;;
            *)
                warn "无效选择，请输入 0-6 之间的数字"
                sleep 1
                ;;
        esac
        
        # 询问是否继续
        echo
        read -p "$(echo -e "${CYAN}是否继续使用优化工具？(y/n): ${NC}")" continue_choice
        case $continue_choice in
            [Nn]|[Nn][Oo])
                echo -e "${YELLOW}感谢使用服务器优化工具！${NC}"
                exit 0
                ;;
            *)
                continue
                ;;
        esac
    done
}

# 主程序
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          服务器优化工具集合 - v$VERSION                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    check_system
    initialize_system
    show_menu_info
    
    # 如果不是通过参数 --install-only 调用，则显示交互菜单
    if [[ "${1:-}" != "--install-only" ]]; then
        interactive_menu
    fi
}

# 执行主程序
main "$@"
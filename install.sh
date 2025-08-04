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
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'

# 日志函数
log() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn() { echo -e "${YELLOW}[注意]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1" >&2; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "需要 root 权限运行此脚本"
        echo "请使用: sudo bash <(curl -sL ss.hide.ss)"
        exit 1
    fi
}

# 获取系统信息
get_system_info() {
    local os_name=""
    local os_version=""
    local kernel_version=""
    
    # 获取内核版本
    kernel_version=$(uname -r 2>/dev/null || echo "未知")
    
    # 优先使用 /etc/os-release (现代Linux标准)
    if [[ -f /etc/os-release ]]; then
        # 避免变量冲突，直接解析文件内容
        os_name=$(grep '^NAME=' /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        os_version=$(grep '^VERSION=' /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        
        # 如果没有VERSION字段，尝试VERSION_ID
        if [[ -z "$os_version" ]]; then
            os_version=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        fi
    # 备用方案：使用 lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        os_name=$(lsb_release -si 2>/dev/null)
        os_version=$(lsb_release -sr 2>/dev/null)
    # 特定系统检测
    else
        # Ubuntu/Debian
        if [[ -f /etc/debian_version ]]; then
            if grep -q "Ubuntu" /etc/issue 2>/dev/null; then
                os_name="Ubuntu"
                os_version=$(cat /etc/debian_version 2>/dev/null || echo "未知版本")
            else
                os_name="Debian"
                os_version=$(cat /etc/debian_version 2>/dev/null || echo "未知版本")
            fi
        # RedHat/CentOS/Fedora
        elif [[ -f /etc/redhat-release ]]; then
            local redhat_info=$(cat /etc/redhat-release 2>/dev/null)
            if echo "$redhat_info" | grep -q "CentOS"; then
                os_name="CentOS"
                os_version=$(echo "$redhat_info" | sed 's/.*release \([0-9.]*\).*/\1/')
            elif echo "$redhat_info" | grep -q "Red Hat"; then
                os_name="Red Hat Enterprise Linux"
                os_version=$(echo "$redhat_info" | sed 's/.*release \([0-9.]*\).*/\1/')
            elif echo "$redhat_info" | grep -q "Fedora"; then
                os_name="Fedora"
                os_version=$(echo "$redhat_info" | sed 's/.*release \([0-9.]*\).*/\1/')
            else
                os_name="RedHat系"
                os_version=$(echo "$redhat_info" | sed 's/.*release \([0-9.]*\).*/\1/' 2>/dev/null || echo "未知版本")
            fi
        # Arch Linux
        elif [[ -f /etc/arch-release ]]; then
            os_name="Arch Linux"
            os_version="滚动发布"
        # openSUSE
        elif [[ -f /etc/SuSE-release ]]; then
            os_name="openSUSE"
            os_version=$(grep "VERSION" /etc/SuSE-release 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "未知版本")
        # Alpine Linux
        elif [[ -f /etc/alpine-release ]]; then
            os_name="Alpine Linux"
            os_version=$(cat /etc/alpine-release 2>/dev/null || echo "未知版本")
        else
            os_name="未知Linux发行版"
            os_version="未知版本"
        fi
    fi
    
    # 确保所有变量都有值
    [[ -z "$os_name" ]] && os_name="未知系统"
    [[ -z "$os_version" ]] && os_version="未知版本"
    [[ -z "$kernel_version" ]] && kernel_version="未知内核"
    
    # 输出系统信息
    echo "${os_name}|${os_version}|${kernel_version}"
}

# 详细系统检查
check_system() {
    log "正在检查系统环境..."
    
    # 获取系统信息
    local system_info=$(get_system_info)
    local os_name=$(echo "$system_info" | cut -d'|' -f1)
    local os_version=$(echo "$system_info" | cut -d'|' -f2)
    local kernel_version=$(echo "$system_info" | cut -d'|' -f3)
    
    # 系统兼容性检查和信息显示
    case "$os_name" in
        *Ubuntu*|*Debian*)
            success "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} ✅"
            ;;
        *CentOS*|*"Red Hat"*|*Fedora*|*RedHat*)
            success "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} ✅"
            ;;
        *Arch*)
            success "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} ✅"
            ;;
        *openSUSE*|*SUSE*)
            success "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} ✅"
            ;;
        *Alpine*)
            warn "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} - 部分功能可能受限 ⚠️"
            ;;
        *)
            warn "检测到 ${os_name} 系统，版本 ${os_version}，内核版本：${kernel_version} - 将尝试继续安装 ⚠️"
            ;;
    esac
    
    # 检查基本命令（静默检查）
    local missing_commands=()
    
    for cmd in curl wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    # 只在缺少命令时提示
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        warn "缺少命令: ${missing_commands[*]} - 建议安装以获得更好体验 ⚠️"
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
    echo
}

# 系统初始化（下载和验证）
initialize_system() {
    log "正在初始化脚本..."
    
    # 执行下载
    install_tools
    
    # 验证安装
    if verify_installation; then
        success "初始化完成 ✅"
    else
        error "初始化失败 ❌"
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
        echo -e "${CYAN}请选择要执行的优化项目：${NC}"
        echo
        echo -e "  ${WHITE}1) TCP网络调优          ${GRAY}# 推荐 - 提升网络性能${NC}"
        echo -e "  ${WHITE}2) DNS服务器配置        ${GRAY}# 推荐 - 提升解析速度${NC}"
        echo -e "  ${WHITE}3) 一键开启BBR          ${GRAY}# 高延迟网络优化${NC}"
        echo -e "  ${WHITE}4) SSH安全配置          ${GRAY}# 端口和密码设置${NC}"
        echo -e "  ${WHITE}5) 禁用IPv6             ${GRAY}# 避免双栈网络问题${NC}"
        echo -e "  ${WHITE}6) 全部优化             ${GRAY}# 运行所有优化项目${NC}"
        echo -e "  ${WHITE}0) 退出程序${NC}"
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
    echo -e "${GREEN}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          服务器优化工具集合 - v$VERSION            ║${NC}"
    echo -e "${GREEN}║          bash <(curl -sL ss.hide.ss)            ║${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════╝${NC}"
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
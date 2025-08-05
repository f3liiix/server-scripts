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
readonly MAGENTA='\033[0;35m'
readonly GRAY='\033[0;37m'
readonly DARK_GRAY='\033[1;30m'
readonly NC='\033[0m'

# 日志函数
log() { 
    echo -e "${BLUE}[信息]${NC} $1"
}

success() { 
    echo -e "${GREEN}[成功]${NC} $1"
}

warn() { 
    echo -e "${YELLOW}[注意]${NC} $1"
}

error() { 
    echo -e "${RED}[错误]${NC} $1" >&2
}

info() {
    echo -e "${CYAN}[信息]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "需要 root 权限运行此脚本"
        echo "请使用: sudo bash <(curl -sL ss.hide.ss)"
        exit 1
    fi
}

# 检测发行版和版本
detect_system() {
    local distro=""
    local version=""
    
    if [[ -f /etc/os-release ]]; then
        # 使用grep和cut解析，避免source导致的变量冲突
        distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        version=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        
        # 如果VERSION_ID不存在，尝试使用VERSION
        if [[ "$version" == "unknown" ]]; then
            version=$(grep '^VERSION=' /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        fi
    elif [[ -f /etc/debian_version ]]; then
        distro="debian"
        version=$(cat /etc/debian_version)
    else
        distro="unknown"
        version="unknown"
    fi
    
    echo "$distro:$version"
}

# 显示欢迎界面
show_welcome() {
    clear
    echo -e "${CYAN}"
    echo "███████╗███████╗   ██╗  ██╗██╗██████╗ ███████╗   ███████╗███████╗" 
    echo "██╔════╝██╔════╝   ██║  ██║██║██╔══██╗██╔════╝   ██╔════╝██╔════╝"
    echo "███████╗███████╗   ███████║██║██║  ██║█████╗     ███████╗███████╗"    
    echo "╚════██║╚════██║   ██╔══██║██║██║  ██║██╔══╝     ╚════██║╚════██║"   
    echo "███████║███████║██╗██║  ██║██║██████╔╝███████╗██╗███████║███████║"
    echo "╚══════╝╚══════╝╚═╝╚═╝  ╚═╝╚═╝╚═════╝ ╚══════╝╚═╝╚══════╝╚══════╝"   
    echo "═════════════════════════════════════════════════════════════════"
    echo "                  服务器优化工具合集 - v$VERSION                    "
    echo "                  bash <(curl -sL ss.hide.ss)                    "
    echo -e "${NC}"
    echo
}

# 显示系统信息
show_system_info() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    local kernel_version=$(uname -r)
    local arch=$(uname -m)
    
    echo -e "${BLUE}🖥️  系统信息${NC}"
    echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
    echo -e "操作系统 : ${WHITE}$distro $version${NC}"
    echo -e "内核版本 : ${WHITE}$kernel_version${NC}"
    echo -e "系统架构 : ${WHITE}$arch${NC}"
    echo
}

# 检查系统兼容性
check_system() {
    log "正在检查系统环境..."
    
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    local kernel_version=$(uname -r)
    
    success "检测到系统: $distro $version，内核：$kernel_version ✅"
    
    # 检查基本命令
    local missing_commands=()
    for cmd in curl wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        warn "缺少命令: ${missing_commands[*]} - 建议安装以获得更好体验 ⚠️"
    fi
}

# 下载并安装
install_tools() {
    echo -e "${BLUE}📥 正在下载所需文件...${NC}"
    echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # 下载主要脚本文件
    local files=(
        "scripts/common_functions.sh"
        "scripts/run_optimization.sh"
        "scripts/system_update.sh"
        "scripts/disable_ipv6.sh"
        "scripts/tcp_tuning.sh"
        "scripts/enable_bbr.sh"
        "scripts/configure_ssh.sh"
        "scripts/configure_dns.sh"
        "scripts/server_config.conf"
    )
    
    local total_files=${#files[@]}
    local current=0
    
    for file in "${files[@]}"; do
        ((current++))
        local dir=$(dirname "$file")
        mkdir -p "$dir"
        
        # 显示进度
        echo -ne "${CYAN}[${current}/${total_files}]${NC} 正在下载 ${WHITE}$file${NC} ... "
        
        # 静默下载，只在失败时输出错误
        if curl -fsSL "$RAW_BASE/$file" -o "$file" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            error "下载失败: $file"
            exit 1
        fi
    done
    
    echo
    echo -e "${BLUE}🔧 正在设置文件权限...${NC}"
    echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
    
    # 设置权限
    find . -name "*.sh" -exec chmod +x {} \;
    chown -R root:root "$INSTALL_DIR" 2>/dev/null || true
    
    echo -e "${GREEN}✓${NC} 权限设置完成"
    echo
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

# 系统初始化（下载和验证）
initialize_system() {
    log "正在初始化脚本..."
    
    # 执行下载
    install_tools
    
    # 验证安装
    if verify_installation; then
        success "脚本初始化完成 ✅"
    else
        error "脚本初始化失败 ❌"
        exit 1
    fi

    echo
}

# 运行优化脚本
run_optimization() {
    local option="$1"
    local main_script="$INSTALL_DIR/scripts/run_optimization.sh"
    
    if [[ -x "$main_script" ]]; then
        if ! bash "$main_script" "$option"; then
            error "优化脚本执行失败，但将继续运行"
            return 1
        fi
    else
        error "优化脚本未找到或无执行权限"
        return 1
    fi
}

# 交互式菜单
interactive_menu() {
    local show_header="${1:-true}"  # 默认显示标题框
    
    while true; do
        # 根据参数决定是否显示标题框
        if [[ "$show_header" == "true" ]]; then
            clear
            echo -e "${CYAN}"
            echo "███████╗███████╗   ██╗  ██╗██╗██████╗ ███████╗   ███████╗███████╗" 
            echo "██╔════╝██╔════╝   ██║  ██║██║██╔══██╗██╔════╝   ██╔════╝██╔════╝"
            echo "███████╗███████╗   ███████║██║██║  ██║█████╗     ███████╗███████╗"    
            echo "╚════██║╚════██║   ██╔══██║██║██║  ██║██╔══╝     ╚════██║╚════██║"   
            echo "███████║███████║██╗██║  ██║██║██████╔╝███████╗██╗███████║███████║"
            echo "╚══════╝╚══════╝╚═╝╚═╝  ╚═╝╚═╝╚═════╝ ╚══════╝╚═╝╚══════╝╚══════╝"   
            echo "═════════════════════════════════════════════════════════════════"
            echo "                  服务器优化工具合集 - v$VERSION                    "
            echo "                  bash <(curl -sL ss.hide.ss)                    "
            echo -e "${NC}"
            echo
            show_system_info
        fi
        
        echo -e "${BLUE}🛠️  功能菜单${NC}"
        echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}1${NC}) 🔄 更新系统/软件包      ${GRAY}# 推荐${NC}"
        echo -e "  ${GREEN}2${NC}) 🚀 开启BBR              ${GRAY}# 推荐${NC}"
        echo -e "  ${GREEN}3${NC}) 🌐 TCP网络调优          ${GRAY}# 推荐${NC}"
        echo -e "  ${GREEN}4${NC}) ⚡ 一键网络优化         ${GRAY}# 一键运行1、2、3项${NC}"
        echo -e "  ${DARK_GRAY}────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}5${NC}) 🌍 DNS服务器配置        ${GRAY}# 修改服务器DNS${NC}"
        echo -e "  ${GREEN}6${NC}) 🔐 SSH安全配置          ${GRAY}# SSH端口和密码修改${NC}"
        echo -e "  ${GREEN}7${NC}) 🚫 禁用IPv6             ${GRAY}# 避免双栈网络问题${NC}"
        echo -e "  ${DARK_GRAY}────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}0${NC}) 🚪 退出脚本"
        echo
        
        read -p "$(echo -e "${YELLOW}请输入选择 (0-7): ${NC}")" choice
        
        case $choice in
            1)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [更新系统及软件包]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "update"
                ;;
            2)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [一键开启BBR]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "bbr"
                ;;
            3)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [TCP网络调优]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "tcp"
                ;;
            4)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [基础优化套餐]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "basic"
                ;;
            5)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [DNS服务器配置]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "dns"
                ;;
            6)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [SSH安全配置]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "ssh"
                ;;
            7)
                echo
                echo -e "${BLUE}▶▶▶ 正在执行 [禁用IPv6]${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                run_optimization "ipv6"
                ;;
            0)
                echo
                echo -e "${GREEN}👋 感谢使用本脚本合集，再见！${NC}"
                echo
                exit 0
                ;;
            *)
                echo
                warn "无效选择，请输入 0-7 之间的数字"
                sleep 2
                continue
                ;;
        esac
        
        # 只有在子脚本异常退出时才显示"按任意键返回主菜单"
        echo
        echo -e "${CYAN}按任意键返回主菜单...${NC}"
        read -n 1 -s
        echo
        
        # 后续循环都显示标题框
        show_header="true"
    done
}

# 主程序
main() {
    # 显示欢迎界面
    show_welcome
    
    # 显示系统信息
    show_system_info
    
    check_root
    check_system
    initialize_system
    
    # 如果不是通过参数 --install-only 调用，则显示交互菜单
    if [[ "${1:-}" != "--install-only" ]]; then
        interactive_menu "false"  # 首次不显示标题框，因为上面已经显示了
    fi
}

# 执行主程序
main "$@"

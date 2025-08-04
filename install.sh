#!/bin/bash

# ==============================================================================
# Script Name: install.sh
# Description: Installation and setup script for server optimization tools
# Author:      Optimized version
# Date:        2025-01-08
# Version:     1.0
# ==============================================================================

set -euo pipefail

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# --- 配置项 ---
readonly SCRIPT_VERSION="1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# --- 日志函数 ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# --- 检查函数 ---

# 检查系统兼容性
check_system() {
    log_step "检查系统兼容性..."
    
    # 检查是否为Linux系统
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "此脚本仅支持Linux系统"
        return 1
    fi
    
    # 检查发行版
    local distro=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
        log_info "检测到系统: $distro $VERSION_ID"
    elif [[ -f /etc/debian_version ]]; then
        distro="debian"
        log_info "检测到系统: Debian $(cat /etc/debian_version)"
    else
        log_warning "无法确定系统发行版，但将继续安装"
    fi
    
    # 检查Bash版本
    local bash_version
    bash_version=$(bash --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
    if [[ "$(printf '%s\n' "$bash_version" "4.0" | sort -V | head -n1)" != "4.0" ]]; then
        log_warning "Bash版本过低 ($bash_version)，建议使用4.0+版本"
    else
        log_success "Bash版本: $bash_version"
    fi
    
    return 0
}

# 检查必要的命令
check_commands() {
    log_step "检查必要的系统命令..."
    
    local required_commands=(
        "sysctl"
        "grep"
        "awk"
        "sed"
        "cat"
        "chmod"
        "cp"
        "mv"
        "mkdir"
        "date"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "缺少必要命令: ${missing_commands[*]}"
        log_info "请安装缺少的命令后重试"
        return 1
    fi
    
    log_success "所有必要命令都已安装"
    return 0
}

# 检查脚本文件
check_script_files() {
    log_step "检查脚本文件完整性..."
    
    local required_scripts=(
        "disable_ipv6.sh"
        "tcp_tuning.sh"
        "enable_bbr.sh"
        "configure_ssh.sh"
        "configure_dns.sh"
        "common_functions.sh"
        "run_optimization.sh"
    )
    
    local missing_files=()
    
    for script in "${required_scripts[@]}"; do
        local script_path="$SCRIPTS_DIR/$script"
        if [[ ! -f "$script_path" ]]; then
            missing_files+=("$script")
        else
            log_info "找到脚本: $script"
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "缺少脚本文件: ${missing_files[*]}"
        return 1
    fi
    
    log_success "所有脚本文件完整"
    return 0
}

# --- 安装函数 ---

# 设置执行权限
set_permissions() {
    log_step "设置脚本执行权限..."
    
    local scripts=(
        "disable_ipv6.sh"
        "tcp_tuning.sh"
        "enable_bbr.sh"
        "configure_ssh.sh"
        "configure_dns.sh"
        "run_optimization.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPTS_DIR/$script"
        if [[ -f "$script_path" ]]; then
            chmod +x "$script_path"
            log_info "设置执行权限: $script"
        fi
    done
    
    # 为通用函数库设置读取权限
    if [[ -f "$SCRIPTS_DIR/common_functions.sh" ]]; then
        chmod +r "$SCRIPTS_DIR/common_functions.sh"
        log_info "设置读取权限: common_functions.sh"
    fi
    
    log_success "权限设置完成"
}

# 创建符号链接（可选）
create_symlinks() {
    log_step "创建便捷命令链接..."
    
    local create_links=false
    
    # 询问用户是否创建全局链接
    echo
    read -p "是否创建全局命令链接? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_links=true
    fi
    
    if [[ "$create_links" == true ]]; then
        # 检查是否有root权限
        if [[ $(id -u) -ne 0 ]]; then
            log_warning "需要root权限创建全局链接，跳过此步骤"
            return 0
        fi
        
        local link_dir="/usr/local/bin"
        local main_script="$SCRIPTS_DIR/run_optimization.sh"
        local link_name="server-optimize"
        
        if [[ -f "$main_script" ]]; then
            ln -sf "$main_script" "$link_dir/$link_name"
            log_success "创建全局命令: $link_name"
            log_info "现在可以使用 'sudo $link_name tcp' 运行优化脚本"
        fi
    else
        log_info "跳过创建全局链接"
    fi
}

# 验证安装
verify_installation() {
    log_step "验证安装结果..."
    
    local verification_passed=true
    
    # 检查脚本执行权限
    local scripts=(
        "disable_ipv6.sh"
        "tcp_tuning.sh"
        "enable_bbr.sh"
        "configure_ssh.sh"
        "configure_dns.sh"
        "run_optimization.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPTS_DIR/$script"
        if [[ ! -x "$script_path" ]]; then
            log_error "$script 不可执行"
            verification_passed=false
        fi
    done
    
    # 测试主控制脚本
    if [[ -x "$SCRIPTS_DIR/run_optimization.sh" ]]; then
        if "$SCRIPTS_DIR/run_optimization.sh" --version >/dev/null 2>&1; then
            log_success "主控制脚本工作正常"
        else
            log_warning "主控制脚本可能存在问题"
            verification_passed=false
        fi
    fi
    
    if [[ "$verification_passed" == true ]]; then
        log_success "安装验证通过"
        return 0
    else
        log_error "安装验证失败"
        return 1
    fi
}

# 显示使用说明
show_usage_info() {
    echo
    echo "=== 🎉 安装完成！ ==="
    echo
    echo "📁 脚本位置: $SCRIPTS_DIR"
    echo
    echo "🚀 快速开始:"
    echo "  # 运行IPv6禁用"
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh ipv6"
    echo
    echo "  # 运行TCP优化"  
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh tcp"
    echo
    echo "  # 启用BBR拥塞控制"
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh bbr"
    echo
    echo "  # SSH安全配置"
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh ssh"
    echo
    echo "  # DNS服务器配置"
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh dns"
    echo
    echo "  # 运行所有优化"
    echo "  sudo $SCRIPTS_DIR/run_optimization.sh all"
    echo
    echo "  # 查看帮助"
    echo "  $SCRIPTS_DIR/run_optimization.sh --help"
    echo
    echo "📖 更多信息请查看 README.md"
    echo
}

# 显示帮助信息
show_help() {
    cat << EOF
服务器优化脚本安装程序 v$SCRIPT_VERSION

用法: $0 [选项]

选项:
  -h, --help     显示此帮助信息
  -v, --version  显示版本信息
  --check-only   仅进行系统检查，不执行安装
  --no-links     跳过创建符号链接
  --force        强制安装（跳过确认）

描述:
  此脚本将为服务器优化工具集合设置执行权限和进行基本配置。
  
  包含的优化脚本:
  - disable_ipv6.sh     IPv6禁用脚本
  - tcp_tuning.sh       TCP网络优化脚本
  - enable_bbr.sh       BBR拥塞控制启用脚本
  - configure_ssh.sh    SSH安全配置脚本
  - configure_dns.sh    DNS服务器配置脚本
  - run_optimization.sh 主控制脚本

示例:
  $0                    # 标准安装
  $0 --check-only       # 仅检查系统兼容性
  $0 --no-links         # 安装但不创建全局链接

EOF
}

# 显示版本信息
show_version() {
    echo "服务器优化脚本安装程序 v$SCRIPT_VERSION"
}

# --- 主程序 ---
main() {
    local check_only=false
    local create_links=true
    local force_install=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --check-only)
                check_only=true
                ;;
            --no-links)
                create_links=false
                ;;
            --force)
                force_install=true
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # 显示欢迎信息
    echo "=== 服务器优化脚本安装程序 v$SCRIPT_VERSION ==="
    echo
    
    # 系统检查
    if ! check_system; then
        exit 1
    fi
    
    if ! check_commands; then
        exit 1
    fi
    
    if ! check_script_files; then
        exit 1
    fi
    
    # 如果只是检查模式，在这里退出
    if [[ "$check_only" == true ]]; then
        log_success "系统检查完成，环境满足安装要求"
        exit 0
    fi
    
    # 用户确认
    if [[ "$force_install" != true ]]; then
        echo
        read -p "确定要继续安装吗? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
    fi
    
    # 执行安装
    log_step "开始安装..."
    
    # 设置权限
    if ! set_permissions; then
        log_error "权限设置失败"
        exit 1
    fi
    
    # 创建符号链接
    if [[ "$create_links" == true ]]; then
        create_symlinks
    fi
    
    # 验证安装
    if ! verify_installation; then
        log_error "安装验证失败"
        exit 1
    fi
    
    # 显示使用说明
    show_usage_info
    
    log_success "安装完成！"
}

# 执行主程序
main "$@" 
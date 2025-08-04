#!/bin/bash

# ==============================================================================
# Script Name: common_functions.sh
# Description: Common utility functions for server optimization scripts
# Author:      f3liiix
# Date:        2025-08-05
# Version:     1.0.0
# ==============================================================================

# 防止重复加载
if [[ "${COMMON_FUNCTIONS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly COMMON_FUNCTIONS_LOADED="true"

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# --- 日志函数 ---
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[注意]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[步骤]${NC} $1"
}

# --- 系统检测函数 ---

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
    elif [[ -f /etc/redhat-release ]]; then
        distro="rhel"
        version=$(grep -o '[0-9]\+\.[0-9]\+' /etc/redhat-release | head -1)
    else
        distro="unknown"
        version="unknown"
    fi
    
    echo "$distro:$version"
}

# 获取系统发行版名称
get_system_distro() {
    local system_info
    system_info=$(detect_system)
    echo "${system_info%:*}"
}

# 获取系统版本
get_system_version() {
    local system_info
    system_info=$(detect_system)
    echo "${system_info#*:}"
}

# 获取系统架构
get_system_arch() {
    uname -m
}

# 获取系统位数
get_system_bits() {
    getconf LONG_BIT 2>/dev/null || echo "unknown"
}

# 检查是否为Debian系发行版
is_debian_based() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    
    case "$distro" in
        "debian"|"ubuntu"|"mint")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查内核版本
get_kernel_version() {
    uname -r | cut -d. -f1,2
}

# 版本比较函数 (返回0表示version1 >= version2)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    if [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version2" ]]; then
        return 0  # version1 >= version2
    else
        return 1  # version1 < version2
    fi
}

# --- 权限和安全检查 ---

# 检查root权限
check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        return 1
    fi
    return 0
}

# 检查用户确认
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        read -p "$message (Y/n): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
    else
        read -p "$message (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || return 1
    fi
    
    return 0
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查服务是否运行
is_service_running() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl is-active "$service" >/dev/null 2>&1
    elif command_exists service; then
        service "$service" status >/dev/null 2>&1
    else
        log_warning "无法检查服务状态: $service"
        return 1
    fi
}

# 获取系统基本信息
get_system_info() {
    echo "=== 系统信息 ==="
    echo "操作系统: $(get_system_distro) $(get_system_version)"
    echo "内核版本: $(get_kernel_version)"
    echo "系统架构: $(get_system_arch) ($(get_system_bits)位)"
    echo "================"
}

# 显示系统信息 (get_system_info的别名，保持兼容性)
show_system_info() {
    get_system_info
}

# --- 包管理器检测和使用 ---

# 检测包管理器
detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists yum; then
        echo "yum"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 更新包列表
update_package_list() {
    local pm
    pm=$(detect_package_manager)
    
    case "$pm" in
        "apt")
            apt-get update -qq
            ;;
        "yum"|"dnf")
            "$pm" check-update -q || true
            ;;
        *)
            log_warning "未知包管理器，请手动更新包列表"
            ;;
    esac
}
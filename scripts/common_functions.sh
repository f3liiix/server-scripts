#!/bin/bash

# ==============================================================================
# Script Name: common_functions.sh
# Description: Common utility functions for server optimization scripts
# Author:      Optimized version
# Date:        2025-01-08
# Version:     1.0
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

log_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# --- 系统检测函数 ---

# 检测发行版和版本
detect_system() {
    local distro=""
    local version=""
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
        version="$VERSION_ID"
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

# 检查内核版本是否满足最低要求
check_kernel_version() {
    local min_version="$1"
    local current_version
    current_version=$(get_kernel_version)
    
    if version_compare "$current_version" "$min_version"; then
        log_success "内核版本 $current_version 满足要求 (>= $min_version)"
        return 0
    else
        log_warning "内核版本 $current_version 不满足要求 (需要 >= $min_version)"
        return 1
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

# --- 文件操作函数 ---

# 安全创建备份文件
create_backup() {
    local source_file="$1"
    local backup_suffix="${2:-.bak.$(date +%Y%m%d_%H%M%S)}"
    
    if [[ -f "$source_file" ]]; then
        local backup_file="${source_file}${backup_suffix}"
        cp "$source_file" "$backup_file"
        log_info "已创建备份: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "源文件不存在: $source_file"
        return 1
    fi
}

# 检查文件是否包含指定内容
file_contains() {
    local file="$1"
    local pattern="$2"
    
    [[ -f "$file" ]] && grep -Fq "$pattern" "$file"
}

# 安全地向文件添加内容（避免重复）
append_to_file() {
    local file="$1"
    local content="$2"
    local marker="$3"
    
    if [[ -n "$marker" ]] && file_contains "$file" "$marker"; then
        log_info "检测到已存在的配置标记，跳过添加"
        return 0
    fi
    
    echo "$content" >> "$file"
    log_success "内容已添加到 $file"
}

# --- 系统服务检查 ---

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

# 启动服务
start_service() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl start "$service"
    elif command_exists service; then
        service "$service" start
    else
        log_error "无法启动服务: $service"
        return 1
    fi
}

# --- 网络检查函数 ---

# 检查网络连接
check_network() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-5}"
    
    if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
        log_success "网络连接正常"
        return 0
    else
        log_warning "网络连接检查失败"
        return 1
    fi
}

# 检查端口是否开放
is_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if command_exists nc; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null
    elif command_exists telnet; then
        timeout "$timeout" telnet "$host" "$port" </dev/null >/dev/null 2>&1
    else
        log_warning "无法检查端口 $host:$port (缺少nc或telnet)"
        return 1
    fi
}

# --- 系统信息收集 ---

# 获取系统基本信息
get_system_info() {
    echo "=== 系统信息 ==="
    echo "操作系统: $(detect_system)"
    echo "内核版本: $(uname -r)"
    echo "架构: $(uname -m)"
    echo "CPU: $(nproc) 核心"
    echo "内存: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo "==============="
}

# 显示脚本执行环境
show_environment() {
    log_info "脚本执行环境:"
    log_info "- 用户: $(whoami)"
    log_info "- 工作目录: $(pwd)"
    log_info "- Shell: $SHELL"
    log_info "- 时间: $(date)"
}

# --- 错误处理和清理 ---

# 设置错误陷阱
setup_error_handling() {
    local cleanup_function="$1"
    
    set -euo pipefail
    
    if [[ -n "$cleanup_function" ]]; then
        trap "$cleanup_function" ERR EXIT
    fi
}

# 清除错误陷阱
clear_error_handling() {
    trap - ERR EXIT
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

# 安装包
install_package() {
    local package="$1"
    local pm
    pm=$(detect_package_manager)
    
    case "$pm" in
        "apt")
            apt-get install -y "$package"
            ;;
        "yum"|"dnf")
            "$pm" install -y "$package"
            ;;
        "pacman")
            pacman -S --noconfirm "$package"
            ;;
        *)
            log_error "无法安装包 $package：未知包管理器"
            return 1
            ;;
    esac
}

# --- 实用工具函数 ---

# 生成随机字符串
generate_random_string() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# 计算文件哈希
calculate_file_hash() {
    local file="$1"
    local algorithm="${2:-sha256}"
    
    if command_exists "${algorithm}sum"; then
        "${algorithm}sum" "$file" | cut -d' ' -f1
    else
        log_error "哈希算法 $algorithm 不可用"
        return 1
    fi
}

# 等待用户按键
wait_for_keypress() {
    local message="${1:-按任意键继续...}"
    read -n 1 -s -r -p "$message"
    echo
}

# 显示进度条
show_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%*s" "$filled" | tr ' ' '='
    printf "%*s" "$empty" | tr ' ' '-'
    printf "] %d%%" "$percentage"
}

# --- 日志轮转 ---

# 创建日志文件
create_log_file() {
    local log_file="$1"
    local max_size="${2:-10M}"
    
    # 创建日志目录
    mkdir -p "$(dirname "$log_file")"
    
    # 如果日志文件过大，进行轮转
    if [[ -f "$log_file" ]] && [[ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file") -gt $((10*1024*1024)) ]]; then
        mv "$log_file" "${log_file}.old"
    fi
    
    touch "$log_file"
    echo "$log_file"
}

# --- 模块加载完成 ---
log_debug "通用函数库加载完成" 
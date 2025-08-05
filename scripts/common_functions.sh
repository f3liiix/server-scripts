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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 配置项 ---
readonly CONFIG_FILE="$SCRIPT_DIR/server_config.conf"
readonly DEFAULT_LOG_FILE="/var/log/server_optimization.log"

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly MAGENTA='\033[0;35m'
readonly GRAY='\033[0;37m'
readonly DARK_GRAY='\033[1;30m'
readonly NC='\033[0m' # No Color

# --- 配置加载函数 ---
load_config() {
    # 获取脚本目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local config_file="$script_dir/server_config.conf"
    
    # 如果配置文件存在，则加载它
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null || {
            echo "警告: 无法加载配置文件 $config_file" >&2
        }
    fi
}

# 加载配置
load_config

# 确定日志文件路径
# 支持从配置文件或环境变量加载LOG_FILE
if [[ -z "${LOG_FILE:-}" ]]; then
    # 如果没有设置LOG_FILE，则尝试从配置中加载
    LOG_FILE="$DEFAULT_LOG_FILE"
fi

# --- 日志函数 ---
log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}ℹ️ [信息]${NC} $message"
    echo "[$timestamp] [INFO] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}✅ [成功]${NC} $message"
    echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}⚠️ [注意]${NC} $message"
    echo "[$timestamp] [WARNING] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}❌ [错误]${NC} $message" >&2
    echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_step() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}➡️  [步骤]${NC} $message"
    echo "[$timestamp] [STEP] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# --- 进度和时间统计函数 ---

# 开始脚本执行计时
start_script_timer() {
    SCRIPT_START_TIME=$(date +%s)
    log_info "脚本开始执行，时间: $(date)"
}

# 结束脚本执行计时并显示总耗时
end_script_timer() {
    if [[ $SCRIPT_START_TIME -gt 0 ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - SCRIPT_START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        if [[ $minutes -gt 0 ]]; then
            log_info "脚本执行完成，总耗时: ${minutes}分${seconds}秒"
        else
            log_info "脚本执行完成，总耗时: ${seconds}秒"
        fi
    fi
}

# 开始任务计时
start_task_timer() {
    local task_name="$1"
    CURRENT_TASK="$task_name"
    TASK_START_TIME=$(date +%s)
    log_step "开始执行任务: $task_name"
}

# 结束任务计时并显示耗时
end_task_timer() {
    if [[ $TASK_START_TIME -gt 0 ]] && [[ -n "$CURRENT_TASK" ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - TASK_START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        if [[ $minutes -gt 0 ]]; then
            log_success "任务完成: $CURRENT_TASK (耗时: ${minutes}分${seconds}秒)"
        else
            log_success "任务完成: $CURRENT_TASK (耗时: ${seconds}秒)"
        fi
        
        # 重置任务计时器
        CURRENT_TASK=""
        TASK_START_TIME=0
    fi
}

# 显示进度条
show_progress() {
    local duration="$1"  # 总持续时间（秒）
    local task_name="${2:-处理}"
    local bar_length=40
    local i
    
    for ((i=0; i<=bar_length; i++)); do
        local percent=$((i * 100 / bar_length))
        printf "\r${CYAN}[进度]${NC} %s: [%-${bar_length}s] %d%%" "$task_name" $(printf "#%.0s" $(seq 1 $i)) $percent
        sleep $((duration / bar_length))
    done
    echo -e "${NC}"
}

# 显示阶段进度
progress_stage() {
    local stage="$1"
    local total_stages="$2"
    local bar_length=40
    local percent=$((stage * 100 / total_stages))
    local filled=$((stage * bar_length / total_stages))
    
    printf "\r${CYAN}[进度]${NC} 阶段: [%-${bar_length}s] %d/%d (%d%%)" $(printf "#%.0s" $(seq 1 $filled)) $stage $total_stages $percent
    if [[ $stage -eq $total_stages ]]; then
        echo -e "${NC}\n已完成所有阶段"
    fi
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

# 检查是否为RedHat系发行版
is_redhat_based() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    
    case "$distro" in
        "centos"|"rhel"|"fedora")
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

# 获取系统详细信息
get_system_details() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    local arch=$(uname -m)
    local kernel=$(uname -r)
    
    echo "发行版: $distro"
    echo "版本: $version"
    echo "架构: $arch"
    echo "内核: $kernel"
}

# 检查系统最低要求
check_system_requirements() {
    local min_kernel="$1"
    local supported_distros="$2"
    
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    local kernel=$(get_kernel_version)
    
    # 检查内核版本
    if [[ -n "$min_kernel" ]]; then
        if ! version_compare "$kernel" "$min_kernel"; then
            log_warning "内核版本 $kernel 低于推荐版本 $min_kernel"
        else
            log_success "内核版本 $kernel 满足要求"
        fi
    fi
    
    # 检查发行版支持情况
    if [[ -n "$supported_distros" ]]; then
        if [[ "$supported_distros" == *"$distro"* ]]; then
            log_success "系统发行版 $distro 受支持"
        else
            log_warning "系统发行版 $distro 可能不受支持"
            log_info "支持的发行版: $supported_distros"
        fi
    fi
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

# 验证IPv4地址格式
validate_ipv4() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ ! "$ip" =~ $regex ]]; then
        return 1
    fi
    
    # 检查每个字段是否在0-255范围内
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ "$octet" -lt 0 || "$octet" -gt 255 ]]; then
            return 1
        fi
        # 检查是否有前导零（除了单个0）
        if [[ ${#octet} -gt 1 && "${octet:0:1}" == "0" ]]; then
            return 1
        fi
    done
    
    return 0
}

# 验证密码强度
validate_password_strength() {
    local password="$1"
    local username="${2:-}"
    local min_length="${3:-8}"
    
    local errors=()
    
    # 检查密码长度
    if [[ ${#password} -lt $min_length ]]; then
        errors+=("密码长度至少需要 $min_length 个字符")
    fi
    
    # 检查是否包含用户名
    if [[ -n "$username" ]] && [[ "$password" == *"$username"* ]]; then
        errors+=("密码不能包含用户名")
    fi
    
    # 检查密码复杂度
    local has_upper=false
    local has_lower=false
    local has_digit=false
    local has_special=false
    
    if [[ "$password" =~ [A-Z] ]]; then has_upper=true; fi
    if [[ "$password" =~ [a-z] ]]; then has_lower=true; fi
    if [[ "$password" =~ [0-9] ]]; then has_digit=true; fi
    if [[ "$password" =~ [^A-Za-z0-9] ]]; then has_special=true; fi
    
    local complexity_score=0
    if [[ "$has_upper" == true ]]; then ((complexity_score++)); fi
    if [[ "$has_lower" == true ]]; then ((complexity_score++)); fi
    if [[ "$has_digit" == true ]]; then ((complexity_score++)); fi
    if [[ "$has_special" == true ]]; then ((complexity_score++)); fi
    
    if [[ $complexity_score -lt 3 ]]; then
        errors+=("密码复杂度不足，建议包含大写字母、小写字母、数字和特殊字符中的至少3种")
    fi
    
    # 检查常见弱密码
    local common_passwords=(
        "123456" "password" "123456789" "12345678" "12345" "1234567"
        "1234567890" "qwerty" "abc123" "111111" "password123" "admin"
        "root" "toor" "123123" "test" "guest" "user"
    )
    
    local is_common=false
    for common_pass in "${common_passwords[@]}"; do
        if [[ "$password" == "$common_pass" ]]; then
            is_common=true
            break
        fi
    done
    
    if [[ "$is_common" == true ]]; then
        errors+=("密码过于简单，请勿使用常见密码")
    fi
    
    # 输出错误信息
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_warning "$error"
        done
        return 1
    fi
    
    return 0
}

# --- 错误处理增强函数 ---

# 记录详细的错误信息
log_error_details() {
    local error_message="$1"
    local error_code="${2:-1}"
    local caller="${3:-$(caller 0)}"
    
    log_error "$error_message"
    log_info "错误代码: $error_code"
    log_info "错误位置: $caller"
    
    # 如果有堆栈跟踪，记录它
    if [[ -n "${BASH_SOURCE[*]}" ]]; then
        log_info "脚本堆栈: ${BASH_SOURCE[*]}"
    fi
}

# 增强的回滚函数
safe_rollback() {
    local backup_file="$1"
    local config_file="$2"
    
    if [[ -f "$backup_file" ]]; then
        log_warning "正在回滚配置文件: $config_file"
        if cp "$backup_file" "$config_file" 2>/dev/null; then
            log_success "配置文件已回滚"
        else
            log_error "配置文件回滚失败"
        fi
    else
        log_warning "未找到备份文件: $backup_file"
    fi
}
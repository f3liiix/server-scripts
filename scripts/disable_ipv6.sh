#!/bin/bash

# ==============================================================================
# Script Name: disable_ipv6.sh
# Description: This script disables IPv6 on Debian/Ubuntu systems by updating
#              sysctl settings. Enhanced with better compatibility and error handling.
# Author:      Optimized version
# Date:        2025-01-08
# Version:     2.0
# ==============================================================================

set -euo pipefail  # 严格模式：遇到错误立即退出

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# --- 配置项 ---
readonly SYSCTL_CONF="/etc/sysctl.conf"
readonly BACKUP_SUFFIX=".bak.$(date +%Y%m%d_%H%M%S)"
readonly IPV6_DISABLE_CONFIG=(
    "net.ipv6.conf.all.disable_ipv6 = 1"
    "net.ipv6.conf.default.disable_ipv6 = 1"
    "net.ipv6.conf.lo.disable_ipv6 = 1"
)

# --- 工具函数 ---
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

# 检测发行版
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# 检查系统兼容性
check_compatibility() {
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        "debian"|"ubuntu")
            log_info "检测到支持的系统: $distro"
            ;;
        *)
            log_warning "未明确支持的系统: $distro，但仍将尝试执行"
            read -p "是否继续? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
            ;;
    esac
}

# 创建配置备份
backup_config() {
    if [[ -f "$SYSCTL_CONF" ]]; then
        local backup_file="${SYSCTL_CONF}${BACKUP_SUFFIX}"
        cp "$SYSCTL_CONF" "$backup_file"
        log_info "已创建配置备份: $backup_file"
        echo "$backup_file"
    else
        log_error "配置文件 $SYSCTL_CONF 不存在！"
        exit 1
    fi
}

# 检查IPv6是否已被禁用
is_ipv6_disabled() {
    local status
    if [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
        status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
        [[ "$status" -eq 1 ]]
    else
        log_warning "无法读取IPv6状态文件"
        return 1
    fi
}

# 添加IPv6禁用配置
add_ipv6_config() {
    # 检查配置是否已存在
    if grep -q "net.ipv6.conf.all.disable_ipv6" "$SYSCTL_CONF"; then
        log_info "检测到 $SYSCTL_CONF 中已存在 IPv6 配置"
        
        # 检查当前配置是否正确
        local all_correct=true
        for config_line in "${IPV6_DISABLE_CONFIG[@]}"; do
            if ! grep -Fq "$config_line" "$SYSCTL_CONF"; then
                all_correct=false
                break
            fi
        done
        
        if [[ "$all_correct" == true ]]; then
            log_info "现有配置正确，无需修改"
            return 0
        else
            log_warning "现有配置不完整，将补充缺失项"
        fi
    fi
    
    log_info "正在添加IPv6禁用配置到 $SYSCTL_CONF ..."
    
    # 添加配置到文件末尾
    {
        echo ""
        echo "# --- Added by disable_ipv6.sh script (v2.0) ---"
        echo "# Generated on: $(date)"
        for line in "${IPV6_DISABLE_CONFIG[@]}"; do
            # 只添加不存在的配置行
            if ! grep -Fq "$line" "$SYSCTL_CONF"; then
                echo "$line"
            fi
        done
        echo "# -----------------------------------------"
    } >> "$SYSCTL_CONF"
    
    log_success "配置添加成功"
}

# 应用配置
apply_config() {
    log_info "正在应用sysctl配置..."
    
    if sysctl -p >/dev/null 2>&1; then
        log_success "配置已成功应用"
    else
        log_error "应用sysctl配置时发生错误"
        log_info "尝试只应用IPv6相关配置..."
        
        # 尝试单独应用IPv6配置
        local success=true
        for config_line in "${IPV6_DISABLE_CONFIG[@]}"; do
            local key="${config_line%% =*}"
            local value="${config_line##*= }"
            if ! sysctl -w "${key}=${value}" >/dev/null 2>&1; then
                log_error "无法设置 $key"
                success=false
            fi
        done
        
        if [[ "$success" == false ]]; then
            exit 1
        fi
    fi
}

# 验证IPv6禁用状态
verify_ipv6_disabled() {
    log_info "正在验证IPv6状态..."
    
    if is_ipv6_disabled; then
        log_success "✅ IPv6已成功禁用"
        
        # 显示详细状态
        echo
        echo "=== IPv6 状态详情 ==="
        if command -v sysctl >/dev/null 2>&1; then
            sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null || true
            sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null || true
            sysctl net.ipv6.conf.lo.disable_ipv6 2>/dev/null || true
        fi
        echo "====================="
        
        return 0
    else
        log_error "❌ IPv6禁用验证失败"
        return 1
    fi
}

# 显示后续建议
show_recommendations() {
    echo
    echo "=== 📋 后续建议 ==="
    echo "1. 重启系统以确保所有服务都使用新配置"
    echo "2. 检查应用程序配置，确保不依赖IPv6"
    echo "3. 验证网络服务正常工作: ping google.com"
    echo "4. 如需恢复IPv6，可使用备份文件进行还原"
    echo "================="
}

# 清理和回滚函数
rollback_changes() {
    local backup_file="$1"
    log_warning "正在回滚更改..."
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$SYSCTL_CONF"
        sysctl -p >/dev/null 2>&1 || true
        log_info "已恢复到备份状态"
    fi
}

# --- 主程序 ---
main() {
    echo "=== IPv6 禁用脚本 v2.0 ==="
    echo
    
    # 1. 检查root权限
    if [[ $(id -u) -ne 0 ]]; then
        log_error "此脚本需要以 root 权限运行"
        log_info "请尝试使用 'sudo $0' 来执行"
        exit 1
    fi
    
    # 2. 检查系统兼容性
    check_compatibility
    
    # 3. 检查当前IPv6状态
    if is_ipv6_disabled; then
        log_info "IPv6 已处于禁用状态"
        verify_ipv6_disabled
        exit 0
    fi
    
    # 4. 创建备份
    local backup_file
    backup_file=$(backup_config)
    
    # 5. 设置错误处理
    trap "rollback_changes '$backup_file'" ERR
    
    # 6. 添加配置
    add_ipv6_config
    
    # 7. 应用配置
    apply_config
    
    # 8. 验证结果
    if verify_ipv6_disabled; then
        show_recommendations
        log_success "IPv6 禁用操作完成！"
    else
        log_error "IPv6 禁用失败，请检查系统日志"
        exit 1
    fi
    
    # 清除错误陷阱
    trap - ERR
}

# 执行主程序
main "$@"
#!/bin/bash

# ==============================================================================
# Script Name: disable_ipv6.sh
# Description: This script disables IPv6 on Debian/Ubuntu systems by updating
#              sysctl settings. Enhanced with better compatibility and error handling.
# Author:      f3liiix
# Date:        2025-08-05
# Version:     1.0.0
# ==============================================================================

set -euo pipefail  # 严格模式：遇到错误立即退出

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用函数库
if [[ -f "$SCRIPT_DIR/common_functions.sh" ]]; then
    # shellcheck source=./common_functions.sh
    source "$SCRIPT_DIR/common_functions.sh"
else
    echo "错误: 无法找到通用函数库 common_functions.sh"
    exit 1
fi

# --- 配置项 ---
readonly SYSCTL_CONF="${SYSCTL_CONF:-/etc/sysctl.conf}"
readonly BACKUP_DIR="${IPV6_BACKUP_DIR}_$(date +%Y%m%d_%H%M%S)"
readonly IPV6_DISABLE_CONFIG=(
    "net.ipv6.conf.all.disable_ipv6 = 1"
    "net.ipv6.conf.default.disable_ipv6 = 1"
    "net.ipv6.conf.lo.disable_ipv6 = 1"
)

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
        if cp "$SYSCTL_CONF" "$backup_file"; then
            log_info "已创建配置备份: $backup_file"
            echo "$backup_file"
        else
            log_error "无法创建配置备份: $backup_file"
            return 1
        fi
    else
        log_error "配置文件 $SYSCTL_CONF 不存在！"
        return 1
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
    if grep -q "net.ipv6.conf.all.disable_ipv6" "$SYSCTL_CONF" 2>/dev/null; then
        log_info "检测到 $SYSCTL_CONF 中已存在 IPv6 配置"
        
        # 检查当前配置是否正确
        local all_correct=true
        for config_line in "${IPV6_DISABLE_CONFIG[@]}"; do
            if ! grep -Fq "$config_line" "$SYSCTL_CONF" 2>/dev/null; then
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
            if ! grep -Fq "$line" "$SYSCTL_CONF" 2>/dev/null; then
                echo "$line"
            fi
        done
        echo "# -----------------------------------------"
    } >> "$SYSCTL_CONF" 2>/dev/null || {
        log_error "无法写入配置到 $SYSCTL_CONF"
        return 1
    }
    
    log_success "配置添加成功"
}

# 应用配置
apply_config() {
    log_info "正在应用sysctl配置..."
    
    if sysctl -p >/dev/null 2>&1; then
        log_success "配置已成功应用"
    else
        log_warning "应用sysctl配置时发生错误"
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
            log_error "无法应用IPv6配置"
            return 1
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
        echo
        
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
    echo "3. 如需恢复IPv6，可使用备份文件进行还原"
    echo "==================="
    echo
}

# 清理和回滚函数
rollback_changes() {
    local backup_file="$1"
    log_warning "正在回滚更改..."
    
    if [[ -f "$backup_file" ]]; then
        if cp "$backup_file" "$SYSCTL_CONF"; then
            sysctl -p >/dev/null 2>&1 || true
            log_success "已恢复到备份状态"
        else
            log_error "无法恢复配置文件"
        fi
    else
        log_warning "未找到备份文件: $backup_file"
    fi
}

# --- 主程序 ---
main() {
    echo
    echo -e "${GREEN}🚫 IPv6禁用工具${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    # 1. 检查root权限
    if ! check_root; then
        exit 1
    fi
    
    # 2. 检查系统兼容性
    check_compatibility
    
    # 3. 检查当前IPv6状态
    if is_ipv6_disabled; then
        log_info "IPv6 已处于禁用状态"
        verify_ipv6_disabled
        return 0
    fi
    
    # 4. 创建备份
    local backup_file
    backup_file=$(backup_config) || {
        log_error "创建备份失败"
        exit 1
    }
    
    # 5. 设置错误处理
    trap "rollback_changes '$backup_file'; exit 1" ERR
    
    # 6. 添加配置
    if ! add_ipv6_config; then
        log_error "添加IPv6配置失败"
        exit 1
    fi
    
    # 7. 应用配置
    if ! apply_config; then
        log_error "应用IPv6配置失败"
        exit 1
    fi
    
    # 8. 验证结果
    if verify_ipv6_disabled; then
        show_recommendations
        log_success "IPv6 禁用操作完成！"
        echo
        return 0
    else
        log_error "IPv6 禁用失败，请检查系统日志"
        return 1
    fi
    
    # 清除错误陷阱
    trap - ERR
}

# 执行主程序
main "$@"
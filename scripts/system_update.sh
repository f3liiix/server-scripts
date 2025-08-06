#!/bin/bash

# ==============================================================================
# Script Name: system_update.sh
# Description: Comprehensive system and package update tool with smart package manager detection
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
# 使用配置文件中的变量
readonly BACKUP_DIR="${UPDATE_BACKUP_DIR}_$(date +%Y%m%d_%H%M%S)"
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/system_update.log"

# --- 主要函数 ---

# 检测包管理器
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 更新软件包列表
update_package_list() {
    local pkg_manager="$1"
    
    log_step "更新软件包列表..."
    
    case "$pkg_manager" in
        "apt")
            if ! apt update; then
                log_error "软件包列表更新失败"
                return 1
            fi
            ;;
        "yum"|"dnf")
            if ! $pkg_manager clean all && $pkg_manager makecache; then
                log_error "软件包缓存更新失败"
                return 1
            fi
            ;;
        "pacman")
            if ! pacman -Sy; then
                log_error "软件包数据库同步失败"
                return 1
            fi
            ;;
        "zypper")
            if ! zypper refresh; then
                log_error "软件包仓库刷新失败"
                return 1
            fi
            ;;
        *)
            log_error "不支持的包管理器: $pkg_manager"
            return 1
            ;;
    esac
    
    log_success "软件包列表更新完成"
}

# 升级系统软件包
upgrade_packages() {
    local pkg_manager="$1"
    
    log_step "升级系统软件包..."
    
    case "$pkg_manager" in
        "apt")
            # 使用 -y 自动确认，DEBIAN_FRONTEND=noninteractive 避免交互
            export DEBIAN_FRONTEND=noninteractive
            if ! apt upgrade -y; then
                log_error "软件包升级失败"
                return 1
            fi
            ;;
        "yum")
            if ! yum update -y; then
                log_error "软件包升级失败"
                return 1
            fi
            ;;
        "dnf")
            if ! dnf upgrade -y; then
                log_error "软件包升级失败"
                return 1
            fi
            ;;
        "pacman")
            if ! pacman -Su --noconfirm; then
                log_error "软件包升级失败"
                return 1
            fi
            ;;
        "zypper")
            if ! zypper update -y; then
                log_error "软件包升级失败"
                return 1
            fi
            ;;
        *)
            log_error "不支持的包管理器: $pkg_manager"
            return 1
            ;;
    esac
    
    log_success "软件包升级完成"
}

# 清理系统
cleanup_system() {
    local pkg_manager="$1"
    
    log_step "清理系统缓存和无用软件包..."
    
    case "$pkg_manager" in
        "apt")
            # 自动清理和删除无用软件包
            apt autoremove -y 2>/dev/null || true
            apt autoclean 2>/dev/null || true
            ;;
        "yum"|"dnf")
            $pkg_manager autoremove -y 2>/dev/null || true
            $pkg_manager clean all 2>/dev/null || true
            ;;
        "pacman")
            # 清理包缓存，保留最近3个版本
            pacman -Sc --noconfirm 2>/dev/null || true
            ;;
        "zypper")
            zypper clean -a 2>/dev/null || true
            ;;
    esac
    
    log_success "系统缓存已经清理"
}

# 显示更新总结
show_update_summary() {
    local pkg_manager="$1"
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    log_success "软件包列表已更新"
    log_success "系统软件包已升级"
    log_success "系统缓存已经清理"
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
}

# 主程序
main() {
    echo
    echo -e "${GREEN}🔄 系统更新工具${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    # 检查root权限
    if ! check_root; then
        exit 1
    fi
    
    # 检测包管理器
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    if [[ "$pkg_manager" == "unknown" ]]; then
        log_error "未检测到支持的包管理器"
        log_info "支持的包管理器: apt, yum, dnf, pacman, zypper"
        exit 1
    fi
    log_info "检测到包管理器: $pkg_manager"
    echo
    
    # 确认操作
    if ! confirm_action "确定要更新系统和软件包吗？" "Y"; then
        log_info "用户取消了系统更新操作"
        return 0
    fi
    
    log_info "开始系统更新，这可能需要一会时间..."
    echo
    
    # 执行更新步骤
    if update_package_list "$pkg_manager" && \
       upgrade_packages "$pkg_manager" && \
       cleanup_system "$pkg_manager"; then
        echo
        show_update_summary "$pkg_manager"
        log_success "系统更新完成！"
        return 0
    else
        echo
        log_error "系统更新过程中出现错误"
        return 1
    fi
}

# 错误处理
trap 'log_error "系统更新过程中发生意外错误"; exit 1' ERR

# 执行主程序
main "$@"
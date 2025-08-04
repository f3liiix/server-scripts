#!/bin/bash

# ==============================================================================
# Script Name: run_optimization.sh
# Description: Simplified master script for menu-driven server optimization
# Author:      Optimized version
# Date:        2025-01-08
# Version:     2.0 (Simplified)
# ==============================================================================

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
readonly SCRIPT_VERSION="2.0"

# 可用的优化脚本映射
SCRIPT_KEYS=("ipv6" "tcp" "bbr" "ssh" "dns")
SCRIPT_FILES=("disable_ipv6.sh" "tcp_tuning.sh" "enable_bbr.sh" "configure_ssh.sh" "configure_dns.sh")

# --- 核心函数 ---

# 根据键名获取脚本文件名
get_script_file() {
    local key="$1"
    for i in "${!SCRIPT_KEYS[@]}"; do
        if [[ "${SCRIPT_KEYS[$i]}" == "$key" ]]; then
            echo "${SCRIPT_FILES[$i]}"
            return 0
        fi
    done
    return 1
}

# 检查脚本文件
check_script() {
    local script_key="$1"
    local script_file
    if ! script_file=$(get_script_file "$script_key"); then
        log_error "未知的脚本: $script_key"
        return 1
    fi
    
    local script_path="$SCRIPT_DIR/$script_file"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "脚本文件不存在: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        log_warning "脚本文件不可执行，正在设置执行权限..."
        chmod +x "$script_path"
    fi
    
    return 0
}

# 运行单个脚本
run_script() {
    local script_key="$1"
    local script_file
    if ! script_file=$(get_script_file "$script_key"); then
        log_error "未知的脚本: $script_key"
        return 1
    fi
    
    local script_path="$SCRIPT_DIR/$script_file"
    
    # 检查脚本
    if ! check_script "$script_key"; then
        return 1
    fi
    
    # 执行脚本
    log_info "正在执行: $script_key 优化脚本"
    
    if ! bash "$script_path"; then
        log_error "$script_key 脚本执行失败"
        return 1
    fi
    
    log_success "$script_key 脚本执行成功"
    return 0
}

# 运行所有脚本
run_all_scripts() {
    log_step "运行所有优化脚本..."
    
    local failed_scripts=()
    local total_scripts=${#SCRIPT_KEYS[@]}
    local current=0
    
    for script_key in "${SCRIPT_KEYS[@]}"; do
        ((current++))
        
        echo
        log_info "进度: [$current/$total_scripts] 运行 $script_key"
        
        if ! run_script "$script_key"; then
            failed_scripts+=("$script_key")
            log_warning "$script_key 脚本执行失败，继续执行其他脚本..."
        fi
        
        # 脚本间暂停
        if [[ $current -lt $total_scripts ]]; then
            log_info "等待 3 秒后继续下一个脚本..."
            sleep 3
        fi
    done
    
    # 总结结果
    echo
    echo "=== 执行总结 ==="
    if [[ ${#failed_scripts[@]} -eq 0 ]]; then
        log_success "所有脚本执行成功！"
    else
        log_warning "以下脚本执行失败:"
        for script in "${failed_scripts[@]}"; do
            echo "  - $script"
        done
        return 1
    fi
    echo "==============="
}

# 主程序
main() {
    local target_script="$1"
    
    # 检查参数
    if [[ -z "$target_script" ]]; then
        log_error "请指定要运行的脚本"
        log_info "支持的脚本: ${SCRIPT_KEYS[*]} all"
        exit 1
    fi
    
    # 执行脚本
    if [[ "$target_script" == "all" ]]; then
        run_all_scripts
    elif get_script_file "$target_script" >/dev/null 2>&1; then
        run_script "$target_script"
    else
        log_error "未知的脚本: $target_script"
        log_info "支持的脚本: ${SCRIPT_KEYS[*]} all"
        exit 1
    fi
}

# 执行主程序
main "$@"
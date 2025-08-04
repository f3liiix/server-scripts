#!/bin/bash

# ==============================================================================
# Script Name: run_optimization.sh
# Description: Master script to run server optimization scripts
# Author:      Optimized version
# Date:        2025-01-08
# Version:     1.0
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
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/server_optimization.log"

# 可用的优化脚本
# 使用数组而非关联数组以提高兼容性
SCRIPT_KEYS=("ipv6" "tcp" "bbr" "ssh" "dns")
SCRIPT_FILES=("disable_ipv6.sh" "tcp_tuning.sh" "enable_bbr.sh" "configure_ssh.sh" "configure_dns.sh")

# 获取脚本文件名的函数
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

# --- 脚本函数 ---

# 显示帮助信息
show_help() {
    cat << EOF
服务器优化脚本集合 v$SCRIPT_VERSION

用法: $0 [选项] [脚本名]

可用脚本:
  ipv6        禁用IPv6配置
  tcp         TCP网络优化配置
  bbr         启用BBR拥塞控制算法
  ssh         SSH安全配置（端口和密码）
  dns         DNS服务器配置（Google/Cloudflare/自定义）
  all         运行所有优化脚本

选项:
  -h, --help    显示此帮助信息
  -l, --list    列出所有可用脚本
  -v, --version 显示版本信息
  -d, --debug   启用调试模式
  --dry-run     预览模式（不执行实际操作）
  --force       强制执行（跳过确认）
  --log FILE    指定日志文件路径

示例:
  $0 ipv6                    # 运行IPv6禁用脚本
  $0 tcp                     # 运行TCP优化脚本
  $0 bbr                     # 启用BBR拥塞控制
  $0 ssh                     # SSH安全配置
  $0 dns                     # DNS服务器配置
  $0 all                     # 运行所有优化脚本
  $0 --dry-run tcp           # 预览TCP优化脚本
  $0 --debug --log /tmp/opt.log dns

EOF
}

# 显示版本信息
show_version() {
    echo "服务器优化脚本集合 v$SCRIPT_VERSION"
    echo "Copyright (c) 2025"
}

# 列出可用脚本
list_scripts() {
    echo "=== 可用的优化脚本 ==="
    for i in "${!SCRIPT_KEYS[@]}"; do
        local key="${SCRIPT_KEYS[$i]}"
        local script_file="${SCRIPT_FILES[$i]}"
        local status="❌ 不存在"
        
        if [[ -f "$SCRIPT_DIR/$script_file" ]]; then
            if [[ -x "$SCRIPT_DIR/$script_file" ]]; then
                status="✅ 可执行"
            else
                status="⚠️ 不可执行"
            fi
        fi
        
        printf "  %-10s %s (%s)\n" "$key" "$script_file" "$status"
    done
    echo "======================"
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
    
    log_step "准备运行脚本: $script_key ($script_file)"
    
    # 检查脚本
    if ! check_script "$script_key"; then
        return 1
    fi
    
    # 预览模式
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "预览模式: 将运行 $script_path"
        return 0
    fi
    
    # 用户确认（除非强制模式）
    if [[ "${FORCE_MODE:-false}" != "true" ]]; then
        if ! confirm_action "确定要运行 $script_key 优化脚本吗？" "Y"; then
            log_info "用户取消了脚本执行"
            return 0
        fi
    fi
    
    # 执行脚本
    log_info "正在执行: $script_path"
    
    if [[ -n "${LOG_FILE:-}" ]]; then
        # 记录到日志文件
        {
            echo "=== 开始执行 $script_key 脚本 $(date) ==="
            bash "$script_path"
            echo "=== 完成执行 $script_key 脚本 $(date) ==="
            echo
        } 2>&1 | tee -a "$LOG_FILE"
    else
        # 直接执行
        bash "$script_path"
    fi
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "$script_key 脚本执行成功"
    else
        log_error "$script_key 脚本执行失败 (退出代码: $exit_code)"
        return $exit_code
    fi
    
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

# 初始化日志
init_logging() {
    if [[ -n "${LOG_FILE:-}" ]]; then
        # 创建日志文件
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir"
        
        # 日志轮转
        if [[ -f "$LOG_FILE" ]]; then
            local log_size
            log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo "0")
            
            # 如果日志文件超过10MB，进行轮转
            if [[ $log_size -gt $((10*1024*1024)) ]]; then
                mv "$LOG_FILE" "${LOG_FILE}.old"
            fi
        fi
        
        touch "$LOG_FILE"
        log_info "日志将记录到: $LOG_FILE"
    fi
}

# 系统预检查
pre_flight_check() {
    log_step "系统预检查..."
    
    # 检查root权限
    if ! check_root; then
        exit 1
    fi
    
    # 检查系统兼容性
    if ! is_debian_based; then
        log_warning "检测到非Debian系统，某些脚本可能不完全兼容"
        if [[ "${FORCE_MODE:-false}" != "true" ]]; then
            if ! confirm_action "是否继续？" "Y"; then
                exit 0
            fi
        fi
    fi
    
    # 显示系统信息
    if [[ "${DEBUG:-false}" == "true" ]]; then
        get_system_info
        show_environment
    fi
    
    log_success "预检查完成"
}

# 主程序
main() {
    local target_script=""
    
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
            -l|--list)
                list_scripts
                exit 0
                ;;
            -d|--debug)
                export DEBUG="true"
                ;;
            --dry-run)
                export DRY_RUN="true"
                ;;
            --force)
                export FORCE_MODE="true"
                ;;
            --log)
                shift
                LOG_FILE="$1"
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$target_script" ]]; then
                    target_script="$1"
                else
                    log_error "只能指定一个脚本"
                    exit 1
                fi
                ;;
        esac
        shift
    done
    
    # 显示欢迎信息
    echo "=== 服务器优化脚本集合 v$SCRIPT_VERSION ==="
    echo
    
    # 初始化日志
    init_logging
    
    # 预检查
    pre_flight_check
    
    # 执行脚本
    if [[ -z "$target_script" ]]; then
        log_error "请指定要运行的脚本"
        echo
        show_help
        exit 1
    elif [[ "$target_script" == "all" ]]; then
        run_all_scripts
    elif get_script_file "$target_script" >/dev/null 2>&1; then
        run_script "$target_script"
    else
        log_error "未知的脚本: $target_script"
        echo
        list_scripts
        exit 1
    fi
}

# 执行主程序
main "$@" 
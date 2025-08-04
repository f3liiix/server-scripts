#!/bin/bash

# ==============================================================================
# Script Name: configure_dns.sh
# Description: DNS configuration script with preset and custom DNS options
# Author:      Optimized version
# Date:        2025-01-08
# Version:     1.0
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
readonly SCRIPT_VERSION="1.0"
readonly RESOLV_CONF="/etc/resolv.conf"
readonly BACKUP_DIR="/etc/backup_dns_$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="/var/log/dns_configuration.log"

# 预设DNS配置 - 使用函数避免关联数组兼容性问题
get_preset_dns() {
    local preset="$1"
    case "$preset" in
        "google") echo "8.8.8.8 8.8.4.4" ;;
        "cloudflare") echo "1.1.1.1 1.0.0.1" ;;
        "ali") echo "223.5.5.5 223.6.6.6" ;;
        "tencent") echo "119.29.29.29 182.254.116.116" ;;
        *) return 1 ;;
    esac
}

get_dns_description() {
    local preset="$1"
    case "$preset" in
        "google") echo "Google Public DNS (快速、可靠)" ;;
        "cloudflare") echo "Cloudflare DNS (隐私保护、快速)" ;;
        "ali") echo "阿里云DNS (国内优化、稳定)" ;;
        "tencent") echo "腾讯DNS (国内快速、智能)" ;;
        *) return 1 ;;
    esac
}

# DNS测试超时时间
readonly DNS_TEST_TIMEOUT=5

# --- DNS配置函数 ---

# 检测DNS管理方式
detect_dns_manager() {
    log_step "检测DNS管理方式..."
    
    local manager=""
    
    # 检查systemd-resolved
    if command_exists systemctl && systemctl is-active systemd-resolved >/dev/null 2>&1; then
        if [[ -L "$RESOLV_CONF" ]] && [[ "$(readlink "$RESOLV_CONF")" == *"systemd"* ]]; then
            manager="systemd-resolved"
        fi
    fi
    
    # 检查NetworkManager
    if [[ -z "$manager" && -f "/etc/NetworkManager/NetworkManager.conf" ]]; then
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
            manager="networkmanager"
        fi
    fi
    
    # 默认为直接管理
    if [[ -z "$manager" ]]; then
        manager="direct"
    fi
    
    log_info "检测到DNS管理方式: $manager"
    echo "$manager"
}

# 获取当前DNS配置
get_current_dns() {
    local current_dns=()
    
    if [[ -f "$RESOLV_CONF" ]]; then
        # 从resolv.conf读取nameserver
        while IFS= read -r line; do
            if [[ "$line" =~ ^nameserver[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
                current_dns+=("${BASH_REMATCH[1]}")
            fi
        done < "$RESOLV_CONF"
    fi
    
    if [[ ${#current_dns[@]} -eq 0 ]]; then
        # 尝试从systemd-resolved获取
        if command_exists systemd-resolve; then
            local resolved_dns
            resolved_dns=$(systemd-resolve --status 2>/dev/null | grep "DNS Servers:" | head -1 | cut -d: -f2 | xargs)
            if [[ -n "$resolved_dns" ]]; then
                IFS=' ' read -ra current_dns <<< "$resolved_dns"
            fi
        fi
    fi
    
    printf '%s\n' "${current_dns[@]}"
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

# 测试DNS服务器可达性
test_dns_server() {
    local dns_server="$1"
    local test_domain="${2:-google.com}"
    
    log_info "测试DNS服务器 $dns_server..."
    
    # 使用nslookup测试
    if command_exists nslookup; then
        if timeout "$DNS_TEST_TIMEOUT" nslookup "$test_domain" "$dns_server" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # 使用dig测试
    if command_exists dig; then
        if timeout "$DNS_TEST_TIMEOUT" dig @"$dns_server" "$test_domain" +short >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # 使用host测试
    if command_exists host; then
        if timeout "$DNS_TEST_TIMEOUT" host "$test_domain" "$dns_server" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# 显示当前DNS配置
show_current_dns() {
    echo
    echo "=== 当前DNS配置 ==="
    
    local current_dns
    current_dns=($(get_current_dns))
    
    if [[ ${#current_dns[@]} -eq 0 ]]; then
        echo "未检测到DNS服务器配置"
    else
        local index=1
        for dns in "${current_dns[@]}"; do
            echo "DNS服务器 $index: $dns"
            ((index++))
        done
    fi
    
    echo "管理方式: $(detect_dns_manager)"
    echo "配置文件: $RESOLV_CONF"
    echo "=================="
}

# 选择预设DNS
select_preset_dns() {
    echo
    echo "=== 预设DNS选项 ==="
    echo "1) Google DNS    - $(get_preset_dns google) ($(get_dns_description google))"
    echo "2) Cloudflare DNS - $(get_preset_dns cloudflare) ($(get_dns_description cloudflare))"
    echo "3) 阿里DNS      - $(get_preset_dns ali) ($(get_dns_description ali))"
    echo "4) 腾讯DNS       - $(get_preset_dns tencent) ($(get_dns_description tencent))"
    echo "5) 自定义DNS"
    echo "6) 返回主菜单"
    echo "=================="
    
    local choice
    while true; do
        read -p "请选择DNS选项 (1-6): " choice
        
        case "$choice" in
            1)
                get_preset_dns "google"
                return 0
                ;;
            2)
                get_preset_dns "cloudflare"
                return 0
                ;;
            3)
                get_preset_dns "ali"
                return 0
                ;;
            4)
                get_preset_dns "tencent"
                return 0
                ;;
            5)
                input_custom_dns
                return 0
                ;;
            6)
                return 1
                ;;
            *)
                log_warning "请输入1-6之间的数字"
                ;;
        esac
    done
}

# 输入自定义DNS
input_custom_dns() {
    local dns_servers=()
    local dns_input
    
    echo
    echo "=== 自定义DNS配置 ==="
    echo "请输入DNS服务器地址（IPv4格式）"
    echo "至少需要1个，最多支持4个DNS服务器"
    echo "直接按回车结束输入"
    echo "======================"
    
    local index=1
    while [[ $index -le 4 ]]; do
        read -p "DNS服务器 $index (可选): " dns_input
        
        # 如果为空且已有至少一个DNS，结束输入
        if [[ -z "$dns_input" ]]; then
            if [[ ${#dns_servers[@]} -gt 0 ]]; then
                break
            else
                log_warning "至少需要输入1个DNS服务器"
                continue
            fi
        fi
        
        # 验证DNS地址格式
        if ! validate_ipv4 "$dns_input"; then
            log_error "无效的IPv4地址格式: $dns_input"
            continue
        fi
        
        # 检查是否重复
        local duplicate=false
        for existing_dns in "${dns_servers[@]}"; do
            if [[ "$existing_dns" == "$dns_input" ]]; then
                log_warning "DNS地址重复: $dns_input"
                duplicate=true
                break
            fi
        done
        
        if [[ "$duplicate" == true ]]; then
            continue
        fi
        
        dns_servers+=("$dns_input")
        log_success "已添加DNS服务器: $dns_input"
        ((index++))
    done
    
    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        log_error "未输入任何有效的DNS服务器"
        return 1
    fi
    
    echo "${dns_servers[*]}"
    return 0
}

# 测试DNS服务器列表
test_dns_servers() {
    local dns_list="$1"
    local dns_array
    IFS=' ' read -ra dns_array <<< "$dns_list"
    
    log_step "测试DNS服务器可达性..."
    
    local working_dns=()
    local failed_dns=()
    
    for dns in "${dns_array[@]}"; do
        if test_dns_server "$dns"; then
            log_success "✅ $dns - 可用"
            working_dns+=("$dns")
        else
            log_warning "❌ $dns - 不可达或响应超时"
            failed_dns+=("$dns")
        fi
    done
    
    echo
    if [[ ${#working_dns[@]} -eq 0 ]]; then
        log_error "所有DNS服务器都无法访问"
        return 1
    elif [[ ${#failed_dns[@]} -gt 0 ]]; then
        log_warning "部分DNS服务器无法访问，但将继续配置可用的服务器"
    else
        log_success "所有DNS服务器测试通过"
    fi
    
    return 0
}

# 备份DNS配置
backup_dns_config() {
    log_step "备份DNS配置..."
    
    mkdir -p "$BACKUP_DIR"
    
    # 备份resolv.conf
    if [[ -f "$RESOLV_CONF" ]]; then
        cp "$RESOLV_CONF" "$BACKUP_DIR/resolv.conf.bak"
        log_info "已备份: $RESOLV_CONF"
    fi
    
    # 备份systemd-resolved配置
    if [[ -f "/etc/systemd/resolved.conf" ]]; then
        cp "/etc/systemd/resolved.conf" "$BACKUP_DIR/resolved.conf.bak"
        log_info "已备份: /etc/systemd/resolved.conf"
    fi
    
    # 记录当前DNS状态
    get_current_dns > "$BACKUP_DIR/current_dns.txt"
    
    log_success "配置备份完成: $BACKUP_DIR"
}

# 应用DNS配置
apply_dns_config() {
    local dns_list="$1"
    local dns_array
    IFS=' ' read -ra dns_array <<< "$dns_list"
    
    log_step "应用DNS配置..."
    
    local manager
    manager=$(detect_dns_manager)
    
    case "$manager" in
        "systemd-resolved")
            apply_systemd_resolved_dns "${dns_array[@]}"
            ;;
        "networkmanager")
            apply_networkmanager_dns "${dns_array[@]}"
            ;;
        "direct")
            apply_direct_dns "${dns_array[@]}"
            ;;
        *)
            log_warning "未知的DNS管理方式，尝试直接配置"
            apply_direct_dns "${dns_array[@]}"
            ;;
    esac
}

# 配置systemd-resolved DNS
apply_systemd_resolved_dns() {
    local dns_servers=("$@")
    local resolved_conf="/etc/systemd/resolved.conf"
    
    log_info "配置systemd-resolved DNS..."
    
    # 修改resolved.conf
    if [[ -f "$resolved_conf" ]]; then
        # 移除现有DNS配置
        sed -i '/^DNS=/d' "$resolved_conf"
        sed -i '/^#DNS=/d' "$resolved_conf"
        
        # 添加新的DNS配置
        local dns_line="DNS=${dns_servers[*]}"
        echo "$dns_line" >> "$resolved_conf"
        
        # 重启systemd-resolved服务
        if systemctl restart systemd-resolved; then
            log_success "systemd-resolved服务重启成功"
        else
            log_error "systemd-resolved服务重启失败"
            return 1
        fi
    else
        log_error "systemd-resolved配置文件不存在"
        return 1
    fi
}

# 配置NetworkManager DNS
apply_networkmanager_dns() {
    local dns_servers=("$@")
    
    log_info "配置NetworkManager DNS..."
    
    # 获取当前活动连接
    local active_connection
    if command_exists nmcli; then
        active_connection=$(nmcli -t -f NAME connection show --active | head -1)
        
        if [[ -n "$active_connection" ]]; then
            # 设置DNS服务器
            local dns_list="${dns_servers[*]}"
            dns_list="${dns_list// /,}"
            
            nmcli connection modify "$active_connection" ipv4.dns "$dns_list"
            nmcli connection modify "$active_connection" ipv4.ignore-auto-dns yes
            
            # 重新激活连接
            nmcli connection up "$active_connection"
            
            log_success "NetworkManager DNS配置成功"
        else
            log_error "未找到活动的网络连接"
            return 1
        fi
    else
        log_error "nmcli命令不可用"
        return 1
    fi
}

# 直接配置DNS
apply_direct_dns() {
    local dns_servers=("$@")
    
    log_info "直接配置DNS到 $RESOLV_CONF..."
    
    # 创建新的resolv.conf内容
    local temp_file
    temp_file=$(mktemp)
    
    # 添加头部注释
    cat > "$temp_file" << EOF
# Generated by configure_dns.sh on $(date)
# Do not edit manually - changes may be overwritten

EOF
    
    # 添加DNS服务器
    for dns in "${dns_servers[@]}"; do
        echo "nameserver $dns" >> "$temp_file"
    done
    
    # 添加通用选项
    cat >> "$temp_file" << EOF

# DNS resolution options
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    # 替换resolv.conf
    if mv "$temp_file" "$RESOLV_CONF"; then
        log_success "DNS配置已写入 $RESOLV_CONF"
        
        # 设置只读属性防止被覆盖
        if command_exists chattr; then
            chattr +i "$RESOLV_CONF" 2>/dev/null || true
        fi
    else
        log_error "无法写入DNS配置文件"
        rm -f "$temp_file"
        return 1
    fi
}

# 验证DNS配置
verify_dns_config() {
    log_step "验证DNS配置..."
    
    # 等待配置生效
    sleep 2
    
    local test_domains=("google.com" "cloudflare.com" "github.com")
    local success_count=0
    
    for domain in "${test_domains[@]}"; do
        log_info "测试域名解析: $domain"
        
        if command_exists nslookup; then
            if timeout "$DNS_TEST_TIMEOUT" nslookup "$domain" >/dev/null 2>&1; then
                log_success "✅ $domain 解析成功"
                ((success_count++))
            else
                log_warning "❌ $domain 解析失败"
            fi
        elif command_exists dig; then
            if timeout "$DNS_TEST_TIMEOUT" dig "$domain" +short >/dev/null 2>&1; then
                log_success "✅ $domain 解析成功"
                ((success_count++))
            else
                log_warning "❌ $domain 解析失败"
            fi
        else
            # 使用ping测试（不太准确但可用）
            if timeout "$DNS_TEST_TIMEOUT" ping -c 1 "$domain" >/dev/null 2>&1; then
                log_success "✅ $domain 连接成功"
                ((success_count++))
            else
                log_warning "❌ $domain 连接失败"
            fi
        fi
    done
    
    echo
    if [[ $success_count -eq ${#test_domains[@]} ]]; then
        log_success "🎉 DNS配置验证成功！所有测试域名都能正常解析"
        return 0
    elif [[ $success_count -gt 0 ]]; then
        log_warning "⚠️ DNS配置部分成功，$success_count/${#test_domains[@]} 个域名解析成功"
        return 0
    else
        log_error "❌ DNS配置验证失败，所有域名都无法解析"
        return 1
    fi
}

# 显示DNS配置结果
show_dns_result() {
    echo
    echo "=== 🌐 DNS配置结果 ==="
    
    local current_dns
    current_dns=($(get_current_dns))
    
    if [[ ${#current_dns[@]} -gt 0 ]]; then
        echo "当前DNS服务器:"
        local index=1
        for dns in "${current_dns[@]}"; do
            # 显示DNS服务器的描述
            local description=""
            if [[ "$dns" == "8.8.8.8" || "$dns" == "8.8.4.4" ]]; then
                description=" (Google DNS)"
            elif [[ "$dns" == "1.1.1.1" || "$dns" == "1.0.0.1" ]]; then
                description=" (Cloudflare DNS)"
            fi
            echo "  $index. $dns$description"
            ((index++))
        done
    else
        echo "未检测到DNS配置"
    fi
    
    echo
    echo "管理方式: $(detect_dns_manager)"
    echo "配置文件: $RESOLV_CONF"
    echo "备份位置: $BACKUP_DIR"
    echo "====================="
}

# 回滚DNS配置
rollback_dns_config() {
    log_warning "正在回滚DNS配置..."
    
    if [[ -d "$BACKUP_DIR" ]]; then
        # 回滚resolv.conf
        if [[ -f "$BACKUP_DIR/resolv.conf.bak" ]]; then
            # 移除只读属性
            if command_exists chattr; then
                chattr -i "$RESOLV_CONF" 2>/dev/null || true
            fi
            
            cp "$BACKUP_DIR/resolv.conf.bak" "$RESOLV_CONF"
            log_info "已恢复 $RESOLV_CONF"
        fi
        
        # 回滚systemd-resolved配置
        if [[ -f "$BACKUP_DIR/resolved.conf.bak" ]]; then
            cp "$BACKUP_DIR/resolved.conf.bak" "/etc/systemd/resolved.conf"
            systemctl restart systemd-resolved 2>/dev/null || true
            log_info "已恢复 systemd-resolved 配置"
        fi
        
        log_success "DNS配置已回滚到修改前状态"
    else
        log_error "未找到备份文件，无法回滚"
    fi
}

# 主菜单
show_main_menu() {
    echo
    echo "=== DNS配置工具 v$SCRIPT_VERSION ==="
    echo "1) 使用预设DNS服务器"
    echo "2) 配置自定义DNS服务器"
    echo "3) 查看当前DNS配置"
    echo "4) 测试DNS解析"
    echo "5) 恢复DNS配置备份"
    echo "6) 退出"
    echo "========================="
}

# 测试当前DNS解析
test_current_dns() {
    log_step "测试当前DNS解析..."
    
    local current_dns
    current_dns=($(get_current_dns))
    
    if [[ ${#current_dns[@]} -eq 0 ]]; then
        log_error "未检测到DNS配置"
        return 1
    fi
    
    echo
    echo "当前DNS服务器:"
    for dns in "${current_dns[@]}"; do
        echo "  - $dns"
    done
    
    verify_dns_config
}

# 恢复DNS备份
restore_dns_backup() {
    echo
    echo "=== DNS备份恢复 ==="
    
    # 查找备份目录
    local backup_dirs
    backup_dirs=($(find /etc -maxdepth 1 -name "backup_dns_*" -type d 2>/dev/null | sort -r))
    
    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        log_error "未找到DNS配置备份"
        return 1
    fi
    
    echo "找到以下备份:"
    for i in "${!backup_dirs[@]}"; do
        local backup_dir="${backup_dirs[$i]}"
        local backup_time
        backup_time=$(basename "$backup_dir" | sed 's/backup_dns_//')
        echo "$((i+1))) $backup_time"
    done
    
    local choice
    read -p "请选择要恢复的备份 (1-${#backup_dirs[@]}): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backup_dirs[@]} ]]; then
        local selected_backup="${backup_dirs[$((choice-1))]}"
        BACKUP_DIR="$selected_backup"
        
        if confirm_action "确定要恢复备份 $(basename "$selected_backup") 吗？" "N"; then
            rollback_dns_config
            return 0
        fi
    else
        log_error "无效的选择"
        return 1
    fi
}

# 主程序
main() {
    echo "=== DNS配置脚本 v$SCRIPT_VERSION ==="
    echo
    
    # 1. 优先处理--help参数（无需root权限）
    if [[ $# -gt 0 ]] && [[ "$1" == "--help" ]]; then
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  --google      使用Google DNS (8.8.8.8, 8.8.4.4)"
        echo "  --cloudflare  使用Cloudflare DNS (1.1.1.1, 1.0.0.1)"
        echo "  --ali         使用阿里云DNS (223.5.5.5, 223.6.6.6)"
        echo "  --tencent     使用腾讯DNS (119.29.29.29, 182.254.116.116)"
        echo "  --test        测试当前DNS解析"
        echo "  --help        显示帮助信息"
        echo ""
        echo "功能说明:"
        echo "  - 配置Google、Cloudflare、阿里云或腾讯DNS服务器"
        echo "  - 支持自定义DNS服务器地址"
        echo "  - 自动检测DNS管理方式并适配"
        echo "  - DNS服务器可达性测试"
        echo "  - 配置文件自动备份和回滚"
        echo ""
        echo "注意: 此脚本需要root权限运行"
        exit 0
    fi
    
    # 2. 权限检查
    if ! check_root; then
        exit 1
    fi
    
    # 3. 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 4. 处理命令行参数
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --google)
                local dns_servers
                dns_servers=$(get_preset_dns "google")
                log_info "配置Google DNS: $dns_servers"
                backup_dns_config
                if test_dns_servers "$dns_servers" && apply_dns_config "$dns_servers" && verify_dns_config; then
                    show_dns_result
                    log_success "Google DNS配置完成！"
                else
                    rollback_dns_config
                    exit 1
                fi
                exit 0
                ;;
            --cloudflare)
                local dns_servers
                dns_servers=$(get_preset_dns "cloudflare")
                log_info "配置Cloudflare DNS: $dns_servers"
                backup_dns_config
                if test_dns_servers "$dns_servers" && apply_dns_config "$dns_servers" && verify_dns_config; then
                    show_dns_result
                    log_success "Cloudflare DNS配置完成！"
                else
                    rollback_dns_config
                    exit 1
                fi
                exit 0
                ;;
            --ali)
                local dns_servers
                dns_servers=$(get_preset_dns "ali")
                log_info "配置阿里云DNS: $dns_servers"
                backup_dns_config
                if test_dns_servers "$dns_servers" && apply_dns_config "$dns_servers" && verify_dns_config; then
                    show_dns_result
                    log_success "阿里云DNS配置完成！"
                else
                    rollback_dns_config
                    exit 1
                fi
                exit 0
                ;;
            --tencent)
                local dns_servers
                dns_servers=$(get_preset_dns "tencent")
                log_info "配置腾讯DNS: $dns_servers"
                backup_dns_config
                if test_dns_servers "$dns_servers" && apply_dns_config "$dns_servers" && verify_dns_config; then
                    show_dns_result
                    log_success "腾讯DNS配置完成！"
                else
                    rollback_dns_config
                    exit 1
                fi
                exit 0
                ;;
            --test)
                test_current_dns
                exit 0
                ;;
        esac
    fi
    
    # 5. 交互式菜单
    while true; do
        show_main_menu
        
        local choice
        read -p "请选择操作 (1-6): " choice
        
        case "$choice" in
            1)
                echo
                local dns_servers
                if dns_servers=$(select_preset_dns); then
                    if test_dns_servers "$dns_servers"; then
                        if confirm_action "确定要配置这些DNS服务器吗？" "Y"; then
                            backup_dns_config
                            if apply_dns_config "$dns_servers" && verify_dns_config; then
                                show_dns_result
                                log_success "DNS配置完成！"
                            else
                                rollback_dns_config
                            fi
                        fi
                    fi
                fi
                ;;
            2)
                echo
                local custom_dns
                if custom_dns=$(input_custom_dns); then
                    if test_dns_servers "$custom_dns"; then
                        if confirm_action "确定要配置这些DNS服务器吗？" "Y"; then
                            backup_dns_config
                            if apply_dns_config "$custom_dns" && verify_dns_config; then
                                show_dns_result
                                log_success "自定义DNS配置完成！"
                            else
                                rollback_dns_config
                            fi
                        fi
                    fi
                fi
                ;;
            3)
                show_current_dns
                ;;
            4)
                test_current_dns
                ;;
            5)
                restore_dns_backup
                ;;
            6)
                log_info "退出DNS配置工具"
                exit 0
                ;;
            *)
                log_warning "请输入1-6之间的数字"
                ;;
        esac
        
        echo
        read -p "按回车键继续..." -r
    done
}

# 执行主程序
main "$@"
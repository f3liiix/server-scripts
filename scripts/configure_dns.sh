#!/bin/bash

# ==============================================================================
# Script Name: configure_dns.sh
# Description: DNS configuration script with preset and custom DNS options
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
readonly SCRIPT_VERSION="1.0.0"
readonly RESOLV_CONF="/etc/resolv.conf"
readonly DNS_BACKUP_DIR="/etc/backup_dns"
readonly BACKUP_DIR="${DNS_BACKUP_DIR}_$(date +%Y%m%d_%H%M%S)"
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
readonly DNS_TEST_TIMEOUT=10

# --- DNS配置函数 ---

# 检测DNS管理方式
detect_dns_manager() {

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
    
    echo "$manager"
}

# 获取当前DNS配置
get_current_dns() {
    local current_dns=()
    local unique_dns=()
    
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
    
    # 去重处理
    local dns
    for dns in "${current_dns[@]}"; do
        local is_duplicate=false
        local unique
        for unique in "${unique_dns[@]}"; do
            if [[ "$dns" == "$unique" ]]; then
                is_duplicate=true
                break
            fi
        done
        
        if [[ "$is_duplicate" == false ]]; then
            unique_dns+=("$dns")
        fi
    done
    
    printf '%s\n' "${unique_dns[@]}"
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
    local test_domains=("baidu.com" "qq.com" "taobao.com" "google.com")
    
    log_info "测试DNS服务器 $dns_server..."
    
    # 首先检查DNS服务器地址是否可达（ping测试）
    if command_exists ping; then
        if ! timeout 5 ping -c 1 "$dns_server" >/dev/null 2>&1; then
            log_warning "❌ $dns_server 网络不可达"
            return 1
        fi
    fi
    
    # 尝试多个测试域名
    for test_domain in "${test_domains[@]}"; do
        # 使用nslookup测试
        if command_exists nslookup; then
            log_info "使用 nslookup 测试 $dns_server ($test_domain)..."
            if timeout "$DNS_TEST_TIMEOUT" nslookup "$test_domain" "$dns_server" >/dev/null 2>&1; then
                log_info "✅ $dns_server 通过 nslookup 测试 ($test_domain)"
                return 0
            fi
        fi
        
        # 使用dig测试
        if command_exists dig; then
            log_info "使用 dig 测试 $dns_server ($test_domain)..."
            if timeout "$DNS_TEST_TIMEOUT" dig @"$dns_server" "$test_domain" +short >/dev/null 2>&1; then
                log_info "✅ $dns_server 通过 dig 测试 ($test_domain)"
                return 0
            fi
        fi
        
        # 使用host测试
        if command_exists host; then
            log_info "使用 host 测试 $dns_server ($test_domain)..."
            if timeout "$DNS_TEST_TIMEOUT" host "$test_domain" "$dns_server" >/dev/null 2>&1; then
                log_info "✅ $dns_server 通过 host 测试 ($test_domain)"
                return 0
            fi
        fi
    done
    
    # 如果所有DNS工具都不可用，尝试ping测试（不太准确但可用）
    if ! command_exists nslookup && ! command_exists dig && ! command_exists host; then
        log_warning "未找到DNS测试工具，尝试ping测试（可能不准确）"
        if timeout "$DNS_TEST_TIMEOUT" ping -c 1 "$dns_server" >/dev/null 2>&1; then
            log_info "✅ $dns_server 通过 ping 测试"
            return 0
        fi
    fi
    
    log_warning "❌ $dns_server 所有测试方法都失败"
    return 1
}

# 输入自定义DNS
input_custom_dns() {
    local dns_servers=()
    local dns_input
    
    echo >&2
    echo "=== 自定义DNS配置 ===" >&2
    echo "请输入DNS服务器地址（IPv4格式）" >&2
    echo "至少需要1个，最多支持2个DNS服务器" >&2
    echo "直接按回车结束输入" >&2
    echo "======================" >&2
    
    local index=1
    while [[ $index -le 2 ]]; do
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
        echo "已添加DNS服务器: $dns_input" >&2
        ((index++))
    done
    
    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        log_error "未输入任何有效的DNS服务器"
        return 1
    fi
    
    # 清理输出，确保没有多余字符，只输出到stdout
    printf '%s' "${dns_servers[*]}"
    return 0
}

# 测试DNS服务器列表
test_dns_servers() {
    local dns_list="$1"
    local dns_array
    
    # 清理输入，移除可能的特殊字符
    dns_list=$(echo "$dns_list" | tr -d "'" | tr -d '"' | xargs)
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
    
    # 清理输入，移除可能的特殊字符
    dns_list=$(echo "$dns_list" | tr -d "'" | tr -d '"' | xargs)
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
    
    # 写入前先移除不可变属性
    if command -v chattr >/dev/null 2>&1; then
        chattr -i "$RESOLV_CONF" 2>/dev/null || true
    fi
    
    # 检查是否为符号链接
    if [[ -L "$RESOLV_CONF" ]]; then
        log_error "检测到 /etc/resolv.conf 是符号链接，可能被 systemd-resolved 或 NetworkManager 管理。请先关闭相关服务的 DNS 管理功能，再重试。"
        rm -f "$temp_file"
        return 1
    fi
    
    if mv "$temp_file" "$RESOLV_CONF"; then
        log_success "DNS配置已写入 $RESOLV_CONF"
        # 设置只读属性防止被覆盖
        if command -v chattr >/dev/null 2>&1; then
            chattr +i "$RESOLV_CONF" 2>/dev/null || true
        fi
    else
        log_error "无法写入DNS配置文件。请检查：1) 是否有root权限；2) /etc/resolv.conf 是否被保护（如 chattr +i）；3) 是否被 systemd-resolved/NetworkManager 管理。"
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
    echo "======================"
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
    
    # 显示当前DNS配置
    show_current_config
    
    echo
    echo "请选择DNS服务器："
    echo "  1) Cloudflare DNS   - 1.1.1.1, 1.0.0.1"
    echo "  2) Google DNS       - 8.8.8.8, 8.8.4.4"
    echo "  3) 阿里DNS          - 223.5.5.5, 223.6.6.6"
    echo "  4) 腾讯DNS          - 119.29.29.29, 182.254.116.116"
    echo "  5) 自定义DNS服务器"
    echo "  6) 恢复DNS配置备份"
    echo "  0) 退出DNS配置工具"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    echo
}

# 显示当前配置（简化版）
show_current_config() {
    echo "当前DNS配置："
    
    local current_dns
    current_dns=($(get_current_dns))
    
    if [[ ${#current_dns[@]} -eq 0 ]]; then
        echo "  未检测到DNS服务器配置"
    else
        for i in "${!current_dns[@]}"; do
            local dns="${current_dns[$i]}"
            local description=""
            
            # 识别常见DNS服务器
            case "$dns" in
                "1.1.1.1"|"1.0.0.1") description=" (Cloudflare)" ;;
                "8.8.8.8"|"8.8.4.4") description=" (Google)" ;;
                "223.5.5.5"|"223.6.6.6") description=" (阿里云)" ;;
                "119.29.29.29"|"182.254.116.116") description=" (腾讯)" ;;
            esac
            
            echo "  DNS $((i+1)): $dns$description"
        done
    fi
}

# 配置预设DNS
configure_preset_dns() {
    local preset="$1"
    local dns_servers
    dns_servers=$(get_preset_dns "$preset")
    local description
    description=$(get_dns_description "$preset")
    
    echo
    echo "DNS服务器: $dns_servers"
    echo
    
    if ! test_dns_servers "$dns_servers"; then
        log_error "DNS服务器测试失败，配置已取消"
        return 1
    fi
    
    echo 

    if confirm_action "确定要配置以上DNS服务器吗？" "Y"; then
        backup_dns_config
        
        if apply_dns_config "$dns_servers" && verify_dns_config; then
            echo
            show_dns_result
            case "$preset" in
                "cloudflare") log_success "Cloudflare DNS配置完成！" ;;
                "google") log_success "Google DNS配置完成！" ;;
                "ali") log_success "阿里云DNS配置完成！" ;;
                "tencent") log_success "腾讯DNS配置完成！" ;;
            esac
        else
            log_error "DNS配置失败，正在回滚..."
            rollback_dns_config
        fi
    else
        log_info "已取消DNS配置"
    fi
}

# 配置自定义DNS
configure_custom_dns() {
    local custom_dns
    
    if custom_dns=$(input_custom_dns); then
        echo >&2
        echo "=== 配置自定义DNS服务器 ===" >&2
        echo "DNS服务器: $custom_dns" >&2
        echo >&2
        
        if ! test_dns_servers "$custom_dns"; then
            log_error "DNS服务器测试失败，配置已取消"
            return 1
        fi
        
        if confirm_action "确定要配置以上DNS服务器吗？" "Y"; then
            backup_dns_config
            
            if apply_dns_config "$custom_dns" && verify_dns_config; then
                echo >&2
                show_dns_result
                log_success "自定义DNS配置完成！"
            else
                log_error "DNS配置失败，正在回滚..."
                rollback_dns_config
            fi
        else
            log_info "已取消DNS配置"
        fi
    else
        log_info "已取消自定义DNS配置"
    fi
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
    # 只保留交互式菜单
    echo
    echo -e "${GREEN}🌍 DNS配置工具${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    while true; do
        show_main_menu
        
        local choice
        read -p "$(echo -e "${YELLOW}请输入选择 (0-6): ${NC}")" choice
        
        case "$choice" in
            1)
                echo
                echo -e "${GREEN}▶▶▶ 配置 Cloudflare DNS${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! configure_preset_dns "cloudflare"; then
                    log_error "Cloudflare DNS配置失败"
                fi
                ;;
            2)
                echo
                echo -e "${GREEN}▶▶▶ 配置 Google DNS${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! configure_preset_dns "google"; then
                    log_error "Google DNS配置失败"
                fi
                ;;
            3)
                echo
                echo -e "${GREEN}▶▶▶ 配置 阿里DNS${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! configure_preset_dns "ali"; then
                    log_error "阿里DNS配置失败"
                fi
                ;;
            4)
                echo
                echo -e "${GREEN}▶▶▶ 配置 腾讯DNS${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! configure_preset_dns "tencent"; then
                    log_error "腾讯DNS配置失败"
                fi
                ;;
            5)
                echo
                echo -e "${GREEN}▶▶▶ 配置 自定义DNS服务器${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! configure_custom_dns; then
                    log_error "自定义DNS配置失败"
                fi
                ;;
            6)
                echo
                echo -e "${GREEN}▶▶▶ 恢复DNS配置备份${NC}"
                echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
                if ! restore_dns_backup; then
                    log_error "DNS备份恢复失败"
                fi
                ;;
            0)
                exit 0
                ;;
            *)
                log_warning "请输入0-6之间的数字"
                ;;
        esac
        
        # 如果不是退出选项，才显示"按任意键返回主菜单"
        if [[ "$choice" != "0" ]]; then
            echo
            echo -e "${CYAN}按任意键返回主菜单...${NC}"
            read -n 1 -s
        fi
    done
}

# 执行主程序
main "$@"
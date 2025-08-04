#!/bin/bash

# ==============================================================================
# Script Name: configure_ssh.sh
# Description: SSH security configuration script for changing port and passwords
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
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly BACKUP_DIR="/etc/backup_ssh_$(date +%Y%m%d_%H%M%S)"
readonly DEFAULT_SSH_PORT="22"
readonly LOG_FILE="/var/log/ssh_configuration.log"

# SSH端口范围
readonly MIN_PORT=1024
readonly MAX_PORT=65535

# --- SSH配置函数 ---

# 检查SSH服务状态
check_ssh_service() {
    
    if ! command_exists sshd && ! command_exists ssh; then
        log_error "SSH服务未安装"
        return 1
    fi
    
    if ! is_service_running ssh && ! is_service_running sshd; then
        log_warning "SSH服务未运行，将尝试启动"
        if command_exists systemctl; then
            systemctl start ssh || systemctl start sshd || {
                log_error "无法启动SSH服务"
                return 1
            }
        elif command_exists service; then
            service ssh start || service sshd start || {
                log_error "无法启动SSH服务"
                return 1
            }
        fi
    fi
    
    log_info "SSH服务运行正常"
    return 0
}

# 获取当前SSH端口
get_current_ssh_port() {
    local current_port
    if [[ -f "$SSHD_CONFIG" ]]; then
        # 查找Port配置行，忽略注释行
        current_port=$(grep -E "^[[:space:]]*Port[[:space:]]+" "$SSHD_CONFIG" | awk '{print $2}' | head -1)
        if [[ -n "$current_port" ]]; then
            echo "$current_port"
        else
            echo "$DEFAULT_SSH_PORT"
        fi
    else
        echo "$DEFAULT_SSH_PORT"
    fi
}

# 验证端口号
validate_port() {
    local port="$1"
    
    # 检查是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "端口号必须是数字"
        return 1
    fi
    
    # 检查端口范围
    if [[ "$port" -lt "$MIN_PORT" ]] || [[ "$port" -gt "$MAX_PORT" ]]; then
        log_error "端口号必须在 $MIN_PORT-$MAX_PORT 范围内"
        return 1
    fi
    
    # 检查端口是否被占用
    if command_exists netstat; then
        if netstat -tuln | grep -q ":$port "; then
            log_warning "端口 $port 可能已被占用"
            if ! confirm_action "是否继续使用此端口？" "N"; then
                return 1
            fi
        fi
    elif command_exists ss; then
        if ss -tuln | grep -q ":$port "; then
            log_warning "端口 $port 可能已被占用"
            if ! confirm_action "是否继续使用此端口？" "N"; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# 输入新SSH端口
input_ssh_port() {
    local current_port
    current_port=$(get_current_ssh_port)
    
    local new_port
    while true; do
        read -p "请输入新的SSH端口 (回车保持当前端口 $current_port): " new_port
        
        # 如果为空，保持当前端口
        if [[ -z "$new_port" ]]; then
            new_port="$current_port"
            log_info "保持当前SSH端口: $new_port"
            break
        fi
        
        # 验证端口
        if validate_port "$new_port"; then
            if [[ "$new_port" == "$current_port" ]]; then
                log_info "端口未变更"
            else
                log_info "新SSH端口: $new_port"
            fi
            break
        else
            log_warning "请输入有效的端口号"
        fi
    done
    
    echo "$new_port"
}

# 修改SSH端口
change_ssh_port() {
    local new_port="$1"
    local current_port
    current_port=$(get_current_ssh_port)
    
    if [[ "$new_port" == "$current_port" ]]; then
        log_info "SSH端口无需更改"
        return 0
    fi
    
    log_step "修改SSH端口从 $current_port 到 $new_port..."
    
    # 创建备份
    if [[ -f "$SSHD_CONFIG" ]]; then
        local backup_file="$BACKUP_DIR/sshd_config.bak"
        mkdir -p "$BACKUP_DIR"
        cp "$SSHD_CONFIG" "$backup_file"
        log_info "已备份SSH配置: $backup_file"
    else
        log_error "SSH配置文件不存在: $SSHD_CONFIG"
        return 1
    fi
    
    # 修改端口配置
    if grep -q "^[[:space:]]*Port[[:space:]]" "$SSHD_CONFIG"; then
        # 替换现有Port行
        sed -i "/^[[:space:]]*Port[[:space:]]/c\Port $new_port" "$SSHD_CONFIG"
    else
        # 添加Port配置
        echo "Port $new_port" >> "$SSHD_CONFIG"
    fi
    
    # 验证配置文件语法
    if ! sshd -t 2>/dev/null; then
        log_error "SSH配置文件语法错误，正在回滚..."
        cp "$backup_file" "$SSHD_CONFIG"
        return 1
    fi
    
    log_success "SSH端口配置已更新"
    return 0
}

# 验证密码强度
validate_password_strength() {
    local password="$1"
    local min_length=8
    
    # 检查密码长度
    if [[ ${#password} -lt $min_length ]]; then
        log_error "密码长度至少需要 $min_length 个字符"
        return 1
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
        log_warning "密码复杂度不足，建议包含:"
        echo "  - 大写字母 (A-Z)"
        echo "  - 小写字母 (a-z)"
        echo "  - 数字 (0-9)"
        echo "  - 特殊字符 (!@#$%^&*)"
        
        if ! confirm_action "是否继续使用此密码？" "N"; then
            return 1
        fi
    fi
    
    return 0
}

# 输入用户密码
input_user_password() {
    local username="$1"
    
    echo
    echo "=== 用户密码配置 ==="
    echo "目标用户: $username"
    echo "密码要求: 至少8位，建议包含大小写字母、数字和特殊字符"
    echo "====================="
    
    local password
    local confirm_password
    local max_attempts=5
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        # 安全输入密码
        read -s -p "请输入新密码: " password
        echo
        
        if [[ -z "$password" ]]; then
            log_warning "密码不能为空 (尝试 $attempts/$max_attempts)"
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "输入次数过多，退出密码设置"
                return 1
            fi
            continue
        fi
        
        # 验证密码强度
        if ! validate_password_strength "$password"; then
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "密码设置次数过多，退出"
                return 1
            fi
            continue
        fi
        
        # 确认密码
        read -s -p "请确认新密码: " confirm_password
        echo
        
        if [[ "$password" != "$confirm_password" ]]; then
            log_error "两次输入的密码不一致，请重新输入 (尝试 $attempts/$max_attempts)"
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "确认密码次数过多，退出密码设置"
                return 1
            fi
            continue
        fi
        
        log_info "密码设置成功"
        break
    done
    
    if [[ -z "$password" ]]; then
        log_error "未能设置有效密码"
        return 1
    fi
    
    echo "$password"
}

# 修改用户密码
change_user_password() {
    local username="$1"
    local password="$2"
    
    log_step "修改用户 $username 的密码..."
    
    # 检查用户是否存在
    if ! id "$username" >/dev/null 2>&1; then
        log_error "用户 $username 不存在"
        return 1
    fi
    
    # 修改密码
    if echo "$username:$password" | chpasswd; then
        log_success "用户 $username 密码修改成功"
        
        # 记录密码修改日志（不记录实际密码）
        echo "$(date): 用户 $username 密码已修改" >> "$LOG_FILE" 2>/dev/null || true
        
        return 0
    else
        log_error "密码修改失败"
        return 1
    fi
}

# 选择用户
select_user() {
    echo
    echo "=== 选择目标用户 ==="
    echo "1) root (系统管理员)"
    echo "2) $(whoami) (当前用户)"
    echo "3) 其他用户 (手动输入)"
    echo "=================="
    
    local choice
    local username
    local max_attempts=5
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        read -p "请选择要修改密码的用户 (1-3): " choice
        
        case "$choice" in
            1)
                username="root"
                log_info "已选择用户: $username"
                break
                ;;
            2)
                username="$(whoami)"
                log_info "已选择用户: $username"
                break
                ;;
            3)
                read -p "请输入用户名: " username
                if [[ -z "$username" ]]; then
                    log_warning "用户名不能为空，请重新选择"
                    continue
                fi
                if ! id "$username" >/dev/null 2>&1; then
                    log_error "用户 $username 不存在，请重新选择"
                    continue
                fi
                log_info "已选择用户: $username"
                break
                ;;
            *)
                log_warning "请输入 1、2 或 3 (尝试 $attempts/$max_attempts)"
                if [[ $attempts -eq $max_attempts ]]; then
                    log_error "选择次数过多，退出用户选择"
                    return 1
                fi
                continue
                ;;
        esac
    done
    
    if [[ -z "$username" ]]; then
        log_error "未能选择有效用户"
        return 1
    fi
    
    echo "$username"
}

# 重启SSH服务
restart_ssh_service() {
    log_step "重启SSH服务..."
    
    local ssh_service
    if command_exists systemctl; then
        # 确定SSH服务名称
        if systemctl is-active ssh >/dev/null 2>&1; then
            ssh_service="ssh"
        elif systemctl is-active sshd >/dev/null 2>&1; then
            ssh_service="sshd"
        else
            ssh_service="ssh"  # 默认尝试ssh
        fi
        
        if systemctl restart "$ssh_service"; then
            log_success "SSH服务重启成功"
        else
            log_error "SSH服务重启失败"
            return 1
        fi
    elif command_exists service; then
        if service ssh restart 2>/dev/null || service sshd restart 2>/dev/null; then
            log_success "SSH服务重启成功"
        else
            log_error "SSH服务重启失败"
            return 1
        fi
    else
        log_warning "无法重启SSH服务，请手动重启"
        return 1
    fi
    
    return 0
}

# 验证SSH配置
verify_ssh_config() {
    log_step "验证SSH配置..."
    
    # 测试SSH配置文件语法
    if ! sshd -t 2>/dev/null; then
        log_error "SSH配置文件语法错误"
        return 1
    fi
    
    # 检查SSH服务状态
    if ! is_service_running ssh && ! is_service_running sshd; then
        log_error "SSH服务未运行"
        return 1
    fi
    
    # 显示当前配置
    local current_port
    current_port=$(get_current_ssh_port)
    
    echo
    echo "=== SSH配置验证结果 ==="
    echo "SSH端口: $current_port"
    echo "SSH服务: ✅ 运行中"
    echo "配置文件: ✅ 语法正确"
    echo "======================"
    
    log_success "SSH配置验证通过"
    return 0
}

# 显示连接提示
show_connection_info() {
    local new_port="$1"
    local server_ip
    
    # 尝试获取服务器IP
    if command_exists curl; then
        server_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    elif command_exists wget; then
        server_ip=$(wget -qO- --timeout=5 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    else
        server_ip="YOUR_SERVER_IP"
    fi
    
    # 验证IP地址格式
    if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$server_ip" != "YOUR_SERVER_IP" ]]; then
        server_ip="YOUR_SERVER_IP"
    fi
    
    echo
    echo "=== 🔐 SSH连接信息 ==="
    echo "服务器地址: $server_ip"
    echo "SSH端口: $new_port"
    echo
    echo "新的SSH连接命令:"
    if [[ "$new_port" != "$DEFAULT_SSH_PORT" ]]; then
        echo "  ssh -p $new_port username@$server_ip"
    else
        echo "  ssh username@$server_ip"
    fi
    echo
    echo "📋 重要提醒:"
    echo "1. 请在新终端测试SSH连接后再关闭当前会话"
    echo "2. 确保防火墙允许新端口的连接"
    echo "3. 如无法连接，请使用服务器控制台恢复配置"
    echo "========================"
}

# 显示防火墙配置建议
show_firewall_suggestions() {
    local new_port="$1"
    
    if [[ "$new_port" == "$DEFAULT_SSH_PORT" ]]; then
        return 0
    fi
    
    echo
    echo "=== 🔥 防火墙配置建议 ==="
    echo "端口已更改，请更新防火墙规则:"
    echo
    
    # UFW
    if command_exists ufw; then
        echo "UFW防火墙:"
        echo "  sudo ufw allow $new_port/tcp"
        echo "  sudo ufw delete allow 22/tcp  # 删除旧规则"
        echo
    fi
    
    # iptables
    if command_exists iptables; then
        echo "iptables防火墙:"
        echo "  sudo iptables -A INPUT -p tcp --dport $new_port -j ACCEPT"
        echo "  sudo iptables -D INPUT -p tcp --dport 22 -j ACCEPT  # 删除旧规则"
        echo
    fi
    
    # firewalld (CentOS/RHEL)
    if command_exists firewall-cmd; then
        echo "firewalld防火墙:"
        echo "  sudo firewall-cmd --permanent --add-port=$new_port/tcp"
        echo "  sudo firewall-cmd --reload"
        echo
    fi
    
    echo "=============================="
}

# 主菜单
show_main_menu() {
    echo
    echo "=== SSH安全配置菜单 ==="
    echo "1) 修改SSH端口"
    echo "2) 修改用户密码"
    echo "3) 同时修改端口和密码"
    echo "4) 查看当前SSH配置"
    echo "0) 退出SSH配置工具"
    echo "======================="
}

# 显示当前配置
show_current_config() {
    local current_port
    current_port=$(get_current_ssh_port)
    
    echo
    echo "=== 当前SSH配置 ==="
    echo "SSH端口: $current_port"
    echo "配置文件: $SSHD_CONFIG"
    
    # 检查服务状态并显示颜色
    if is_service_running ssh || is_service_running sshd; then
        echo -e "服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "服务状态: ${RED}未运行${NC}"
    fi
    
    echo "==================="
}

# 主程序
main() {
    # 1. 优先处理--help参数（无需root权限）
    if [[ $# -gt 0 ]] && [[ "$1" == "--help" ]]; then
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  --port      仅修改SSH端口"
        echo "  --password  仅修改用户密码"
        echo "  --help      显示帮助信息"
        echo ""
        echo "功能说明:"
        echo "  - 修改SSH默认端口（1024-65535）"
        echo "  - 修改用户密码（支持root/当前用户/自定义用户）"
        echo "  - 配置文件自动备份和验证"
        echo "  - 防火墙配置建议"
        echo ""
        echo "注意: 此脚本需要root权限运行"
        exit 0
    fi
    
    # 2. 权限检查
    if ! check_root; then
        exit 1
    fi
    
    # 3. 检查SSH服务
    if ! check_ssh_service; then
        exit 1
    fi
    
    # 4. 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 只保留交互式菜单
    while true; do
        show_main_menu
        
        local choice
        read -p "$(echo -e "${YELLOW}请输入选择 (0-4): ${NC}")" choice
        
        case "$choice" in
            1)
                echo
                log_info "=== 修改SSH端口 ==="
                local new_port
                if ! new_port=$(input_ssh_port); then
                    log_error "端口输入失败"
                    continue
                fi
                
                if ! change_ssh_port "$new_port"; then
                    log_error "SSH端口修改失败"
                elif ! restart_ssh_service; then
                    log_error "SSH服务重启失败"
                else
                    verify_ssh_config
                    show_connection_info "$new_port"
                    show_firewall_suggestions "$new_port"
                fi
                ;;
            2)
                echo
                log_info "=== 修改用户密码 ==="
                local username
                if ! username=$(select_user); then
                    log_error "用户选择失败"
                    continue
                fi
                local password
                if ! password=$(input_user_password "$username"); then
                    log_error "密码输入失败"
                    continue
                fi
                if ! change_user_password "$username" "$password"; then
                    log_error "用户密码修改失败"
                fi
                ;;
            3)
                echo
                log_info "=== 同时修改端口和密码 ==="
                
                # 修改端口
                local new_port
                if ! new_port=$(input_ssh_port); then
                    log_error "端口输入失败"
                    continue
                fi
                
                # 修改密码
                local username
                if ! username=$(select_user); then
                    log_error "用户选择失败"
                    continue
                fi
                local password
                if ! password=$(input_user_password "$username"); then
                    log_error "密码输入失败"
                    continue
                fi
                
                # 执行修改
                local success=true
                if ! change_ssh_port "$new_port"; then
                    log_error "SSH端口修改失败"
                    success=false
                fi
                
                if ! change_user_password "$username" "$password"; then
                    log_error "用户密码修改失败"
                    success=false
                fi
                
                if [[ "$success" == true ]]; then
                    if restart_ssh_service; then
                        verify_ssh_config
                        show_connection_info "$new_port"
                        show_firewall_suggestions "$new_port"
                    else
                        log_error "SSH服务重启失败"
                    fi
                fi
                ;;
            4)
                show_current_config
                ;;
            0)
                log_info "退出SSH配置工具"
                exit 0
                ;;
            *)
                log_warning "请输入 0-4 之间的数字"
                ;;
        esac
        
        echo
        read -p "按回车键继续..." -r
    done
}

# 执行主程序
main "$@"
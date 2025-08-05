#!/bin/bash

# ==============================================================================
# Script Name: configure_ssh.sh
# Description: SSH security configuration script for changing port and passwords
# Author:      f3liiix
# Date:        2025-08-05
# Version:     1.0.0
# ==============================================================================

# 颜色定义
readonly NC='\033[0m'         # No Color
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly DARK_GRAY='\033[1;30m'

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
            break
        fi
        
        # 验证端口
        if validate_port "$new_port"; then
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
    else
        log_error "SSH配置文件不存在: $SSHD_CONFIG"
        return 1
    fi
    
    # 修改端口配置
    if grep -q "^[[:space:]]*Port[[:space:]]" "$SSHD_CONFIG"; then
        # 替换现有Port行，使用更安全的方式
        sed -i "/^[[:space:]]*Port[[:space:]]/c\\Port $new_port" "$SSHD_CONFIG"
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
    local username="$2"
    
    # 使用common_functions.sh中的增强验证函数
    if ! validate_password_strength "$password" "$username" 8; then
        if ! confirm_action "是否继续使用此密码？" "N"; then
            return 1
        fi
    fi
    
    return 0
}

# 输入用户密码
input_user_password() {
    local username="$1"
    
    echo >&2
    echo "=== 用户密码配置 ===" >&2
    echo "目标用户: $username" >&2
    echo "密码要求: 至少8位，建议包含大小写字母、数字和特殊字符" >&2
    echo "=====================" >&2
    
    local password
    local confirm_password
    local max_attempts=5
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        # 安全输入密码
        read -s -p "请输入新密码: " password
        echo >&2
        
        if [[ -z "$password" ]]; then
            log_warning "密码不能为空 (尝试 $attempts/$max_attempts)"
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "输入次数过多，退出密码设置"
                return 1
            fi
            continue
        fi
        
        # 验证密码强度
        if ! validate_password_strength "$password" "$username"; then
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "密码设置次数过多，退出"
                return 1
            fi
            continue
        fi
        
        # 确认密码
        read -s -p "请确认新密码: " confirm_password
        echo >&2
        
        if [[ "$password" != "$confirm_password" ]]; then
            log_error "两次输入的密码不一致，请重新输入 (尝试 $attempts/$max_attempts)"
            if [[ $attempts -eq $max_attempts ]]; then
                log_error "确认密码次数过多，退出密码设置"
                return 1
            fi
            continue
        fi
        
        echo "密码设置成功" >&2
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
    local current_user
    current_user=$(whoami)
    
    echo >&2
    echo "=== 选择目标用户 ===" >&2
    
    # 如果当前用户是root，只显示两个选项
    if [[ "$current_user" == "root" ]]; then
        echo "1) root (系统管理员)" >&2
        echo "2) 其他用户 (手动输入)" >&2
        echo "====================" >&2
        
        local choice
        local username
        local max_attempts=5
        local attempts=0
        
        while [[ $attempts -lt $max_attempts ]]; do
            ((attempts++))
            read -p "请选择要修改密码的用户 (1-2 或直接输入用户名): " choice
            
            case "$choice" in
                1)
                    username="root"
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                2)
                    read -p "请输入用户名: " username
                    if [[ -z "$username" ]]; then
                        log_warning "用户名不能为空，请重新选择"
                        continue
                    fi
                    if ! id "$username" >/dev/null 2>&1; then
                        log_error "用户 $username 不存在，请重新选择"
                        continue
                    fi
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                "root")
                    username="root"
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                *)
                    # 检查是否直接输入了用户名
                    if [[ -n "$choice" ]]; then
                        if id "$choice" >/dev/null 2>&1; then
                            username="$choice"
                            echo "已选择用户: $username" >&2
                            break
                        else
                            log_error "用户 $choice 不存在，请重新选择"
                            if [[ $attempts -eq $max_attempts ]]; then
                                log_error "选择次数过多，退出用户选择"
                                return 1
                            fi
                            continue
                        fi
                    else
                        log_warning "请输入 1、2 或直接输入用户名 (尝试 $attempts/$max_attempts)"
                        if [[ $attempts -eq $max_attempts ]]; then
                            log_error "选择次数过多，退出用户选择"
                            return 1
                        fi
                        continue
                    fi
                    ;;
            esac
        done
    else
        # 当前用户不是root，显示三个选项
        echo "1) root (系统管理员)" >&2
        echo "2) $current_user (当前用户)" >&2
        echo "3) 其他用户 (手动输入)" >&2
        echo "====================" >&2
        
        local choice
        local username
        local max_attempts=5
        local attempts=0
        
        while [[ $attempts -lt $max_attempts ]]; do
            ((attempts++))
            read -p "请选择要修改密码的用户 (1-3 或直接输入用户名): " choice
            
            case "$choice" in
                1)
                    username="root"
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                2)
                    username="$current_user"
                    echo "已选择用户: $username" >&2
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
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                "root")
                    username="root"
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                "$current_user")
                    username="$current_user"
                    echo "已选择用户: $username" >&2
                    break
                    ;;
                *)
                    # 检查是否直接输入了用户名
                    if [[ -n "$choice" ]]; then
                        if id "$choice" >/dev/null 2>&1; then
                            username="$choice"
                            echo "已选择用户: $username" >&2
                            break
                        else
                            log_error "用户 $choice 不存在，请重新选择"
                            if [[ $attempts -eq $max_attempts ]]; then
                                log_error "选择次数过多，退出用户选择"
                                return 1
                            fi
                            continue
                        fi
                    else
                        log_warning "请输入 1、2、3 或直接输入用户名 (尝试 $attempts/$max_attempts)"
                        if [[ $attempts -eq $max_attempts ]]; then
                            log_error "选择次数过多，退出用户选择"
                            return 1
                        fi
                        continue
                    fi
                    ;;
            esac
        done
    fi
    
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
    echo -e "${BLUE}=== 🔐 SSH连接信息 ===${NC}"
    echo -e "  服务器地址: $server_ip"
    echo -e "  SSH端口: ${GREEN}$new_port${NC}"
    echo -e "${DARK_GRAY}========================${NC}"
}

# 显示防火墙配置建议
show_firewall_suggestions() {
    local new_port="$1"
    local current_port
    current_port=$(get_current_ssh_port)
    
    if [[ "$new_port" == "$current_port" ]]; then
        return 0
    fi
    
    echo
    echo -e "${BLUE}=== 🔥 防火墙配置建议 ===${NC}"
    echo -e "${DARK_GRAY}端口已更改，请更新防火墙规则:${NC}"
    echo
    
    # UFW
    if command_exists ufw; then
        echo -e "${CYAN}UFW防火墙:${NC}"
        echo -e "  sudo ${GREEN}ufw allow $new_port/tcp${NC}"
        echo -e "  sudo ${RED}ufw delete allow 22/tcp${NC}  # 删除旧规则"
        echo
    fi
    
    # iptables
    if command_exists iptables; then
        echo -e "${CYAN}iptables防火墙:${NC}"
        echo -e "  sudo ${GREEN}iptables -A INPUT -p tcp --dport $new_port -j ACCEPT${NC}"
        echo -e "  sudo ${RED}iptables -D INPUT -p tcp --dport 22 -j ACCEPT${NC}  # 删除旧规则"
        echo
    fi
    
    # firewalld (CentOS/RHEL)
    if command_exists firewall-cmd; then
        echo -e "${CYAN}firewalld防火墙:${NC}"
        echo -e "  sudo ${GREEN}firewall-cmd --permanent --add-port=$new_port/tcp${NC}"
        echo -e "  sudo ${GREEN}firewall-cmd --reload${NC}"
        echo
    fi
    
    echo -e "${DARK_GRAY}==============================${NC}"
}

# 主菜单
show_main_menu() {
    echo
    echo -e "${BLUE}选择操作:${NC}"
    echo -e "  ${CYAN}1)${NC} 修改SSH端口"
    echo -e "  ${CYAN}2)${NC} 修改用户密码"
    echo -e "  ${CYAN}3)${NC} 同时修改端口和密码"
    echo -e "  ${CYAN}4)${NC} 查看当前SSH配置"
    echo -e "  ${CYAN}0)${NC} 退出SSH配置工具"
}

# 显示当前配置
show_current_config() {
    local current_port
    current_port=$(get_current_ssh_port)
    
    echo
    echo "当前SSH配置:"
    echo -e "  SSH端口: ${BLUE}$current_port${NC}"
    echo -e "  配置文件: $SSHD_CONFIG"
    
    # 检查服务状态并显示颜色
    if is_service_running ssh || is_service_running sshd; then
        echo -e "  服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "  服务状态: ${RED}未运行${NC}"
    fi
}

# 主程序
main() {
    # 只保留交互式菜单
    echo
    echo -e "${BLUE}🔐 SSH安全配置工具${NC}"
    echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
    
    while true; do
        show_main_menu
        
        local choice
        read -p "$(echo -e "${YELLOW}请输入选择 (0-4): ${NC}")" choice
        
        case "$choice" in
            1)
                echo
                echo -e "${BLUE}▶▶▶ 修改SSH端口${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
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
                    show_firewall_suggestions "$new_port"
                fi
                ;;
            2)
                echo
                echo -e "${BLUE}▶▶▶ 修改用户密码${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
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
                echo -e "${BLUE}▶▶▶ 同时修改端口和密码${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                
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
                        show_firewall_suggestions "$new_port"
                    else
                        log_error "SSH服务重启失败"
                    fi
                fi
                ;;
            4)
                echo
                echo -e "${BLUE}▶▶▶ 查看当前SSH配置${NC}"
                echo -e "${DARK_GRAY}────────────────────────────────────────${NC}"
                show_current_config
                ;;
            0)
                log_info "退出SSH配置工具"
                echo
                exit 0
                ;;
            *)
                log_warning "请输入 0-4 之间的数字"
                ;;
        esac
        
        echo
        read -p "$(echo -e "${CYAN}按回车键继续...${NC}")" -r
    done
}

# 执行主程序
main "$@"
#!/bin/bash

# ==============================================================================
# Script Name: tcp_tuning.sh
# Description: Enhanced TCP network optimization script for Debian/Ubuntu systems
#              with better compatibility, error handling, and rollback support.
# Author:      f3liiix
# Date:        2025-08-05
# Version:     1.0.0
# ==============================================================================

set -euo pipefail  # 严格模式：遇到错误立即退出

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# --- 配置项 ---
readonly SCRIPT_VERSION="1.0.0"
readonly BACKUP_DIR="/etc/backup_tcp_tuning_$(date +%Y%m%d_%H%M%S)"
readonly SYSCTL_CONF="/etc/sysctl.conf"
readonly LIMITS_CONF="/etc/security/limits.conf"
readonly MIN_KERNEL_VERSION="4.9"

# --- 工具函数 ---
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[注意]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[步骤]${NC} $1"
}

# 系统检测函数
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

# 检查内核版本
check_kernel_version() {
    local min_version="$1"
    local current_version
    current_version=$(uname -r | cut -d. -f1,2)
    
    if version_compare "$current_version" "$min_version"; then
        log_success "内核版本 $current_version 满足要求 (>= $min_version)"
        return 0
    else
        log_warning "内核版本 $current_version 不满足要求 (需要 >= $min_version)"
        return 1
    fi
}

# 检查系统兼容性
check_system_compatibility() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    
    log_info "检测到系统: $distro $version"
    
    case "$distro" in
        "debian")
            if version_compare "$version" "9"; then
                log_success "Debian $version 完全支持"
            else
                log_warning "Debian $version 可能不完全支持所有功能"
            fi
            ;;
        "ubuntu")
            if version_compare "$version" "16.04"; then
                log_success "Ubuntu $version 完全支持"
            else
                log_warning "Ubuntu $version 可能不完全支持所有功能"
            fi
            ;;
        *)
            log_warning "未明确测试的系统: $distro $version"
            read -p "是否继续? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
            ;;
    esac
}

# 创建备份目录和文件
create_backup() {
    log_step "创建配置文件备份..."
    
    mkdir -p "$BACKUP_DIR"
    
    # 备份关键配置文件
    if [[ -f "$SYSCTL_CONF" ]]; then
        cp "$SYSCTL_CONF" "$BACKUP_DIR/sysctl.conf.bak"
        log_info "已备份 $SYSCTL_CONF"
    fi
    
    if [[ -f "$LIMITS_CONF" ]]; then
        cp "$LIMITS_CONF" "$BACKUP_DIR/limits.conf.bak"
        log_info "已备份 $LIMITS_CONF"
    fi
    
    # 记录当前sysctl状态
    sysctl -a > "$BACKUP_DIR/sysctl_before.txt" 2>/dev/null || true
    
    log_success "备份已创建: $BACKUP_DIR"
}

# 检查BBR模块可用性
check_bbr_availability() {
    local bbr_available=false
    
    # 检查内核是否支持BBR
    if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
            bbr_available=true
        fi
    fi
    
    if [[ "$bbr_available" == true ]]; then
        log_success "BBR拥塞控制算法可用"
        return 0
    else
        log_warning "BBR拥塞控制算法不可用，将使用默认算法"
        return 1
    fi
}

# 检查并设置conntrack参数
configure_conntrack() {
    local conntrack_configured=false
    
    # 先检查conntrack模块是否加载
    if ! lsmod | grep -q nf_conntrack 2>/dev/null && ! lsmod | grep -q ip_conntrack 2>/dev/null; then
        log_warning "conntrack模块未加载，跳过连接追踪优化"
        return 0
    fi
    
    # 尝试不同的conntrack路径
    local conntrack_paths=(
        "/proc/sys/net/netfilter/nf_conntrack_max"
        "/proc/sys/net/nf_conntrack_max"
    )
    
    for path in "${conntrack_paths[@]}"; do
        if [[ -f "$path" ]] && [[ -r "$path" ]] && [[ -w "$path" ]]; then
            # 先测试参数是否可以设置
            local current_value
            current_value=$(cat "$path" 2>/dev/null)
            
            if [[ -n "$current_value" ]]; then
                local param_name="${path#/proc/sys/}"
                param_name="${param_name//\//.}"
                
                # 添加配置到sysctl.conf
                echo "# 连接追踪表大小优化" >> "$SYSCTL_CONF"
                echo "$param_name = 1048576" >> "$SYSCTL_CONF"
                log_info "配置连接追踪参数: $param_name (当前值: $current_value)"
                conntrack_configured=true
                break
            fi
        fi
    done
    
    if [[ "$conntrack_configured" == false ]]; then
        log_warning "未找到有效的conntrack参数路径，跳过连接追踪优化"
        log_info "这在某些系统配置下是正常的（如容器环境或未启用netfilter）"
    fi
}

# 清理无效的conntrack配置
clean_invalid_conntrack_config() {
    log_info "检查并清理无效的conntrack配置..."
    
    # 检查现有配置中是否有无效的conntrack参数
    if grep -q "nf_conntrack_max" "$SYSCTL_CONF"; then
        local has_valid_conntrack=false
        
        # 检查conntrack模块和路径
        if (lsmod | grep -q nf_conntrack 2>/dev/null || lsmod | grep -q ip_conntrack 2>/dev/null); then
            local conntrack_paths=(
                "/proc/sys/net/netfilter/nf_conntrack_max"
                "/proc/sys/net/nf_conntrack_max"
            )
            
            for path in "${conntrack_paths[@]}"; do
                if [[ -f "$path" ]] && [[ -r "$path" ]]; then
                    has_valid_conntrack=true
                    break
                fi
            done
        fi
        
        # 如果没有有效的conntrack支持，移除相关配置
        if [[ "$has_valid_conntrack" == false ]]; then
            log_warning "发现无效的conntrack配置，正在清理..."
            
            # 创建临时文件，过滤掉conntrack相关行
            local temp_conf="/tmp/sysctl_clean.conf"
            grep -v "nf_conntrack_max" "$SYSCTL_CONF" > "$temp_conf"
            
            # 替换原文件
            cp "$temp_conf" "$SYSCTL_CONF"
            rm -f "$temp_conf"
            
            log_success "已清理无效的conntrack配置"
        fi
    fi
}

# 应用TCP优化配置
apply_tcp_optimization() {
    
    # 先清理可能存在的无效配置
    clean_invalid_conntrack_config
    
    # 检查是否已存在配置
    if grep -q "TCP网络调优" "$SYSCTL_CONF"; then
        log_warning "检测到已存在的TCP优化配置，将跳过重复配置"
        return 0
    fi
    
    # 添加TCP优化配置
    cat >> "$SYSCTL_CONF" << 'EOF'

# ===== TCP网络调优 v1.0.0 =====
# 连接队列优化
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192

# 缓冲区优化
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 队列调度算法
net.core.default_qdisc = fq
net.ipv4.tcp_notsent_lowat = 16384

# TIME-WAIT优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 200000

# TCP快速打开
net.ipv4.tcp_fastopen = 3

# TCP窗口缩放
net.ipv4.tcp_window_scaling = 1

# TCP时间戳
net.ipv4.tcp_timestamps = 1

# 内存压力处理
net.ipv4.tcp_mem = 786432 1048576 1572864
EOF

    # 条件性添加BBR配置
    if check_bbr_availability; then
        echo "# BBR拥塞控制算法" >> "$SYSCTL_CONF"
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    else
        echo "# 使用默认拥塞控制算法 (BBR不可用)" >> "$SYSCTL_CONF"
        echo "# net.ipv4.tcp_congestion_control = cubic" >> "$SYSCTL_CONF"
    fi
    
    # 配置conntrack参数
    configure_conntrack
    
    echo "# =============================================" >> "$SYSCTL_CONF"
    
    log_success "TCP优化配置已添加"
}

# 应用文件描述符限制优化
apply_ulimit_optimization() {
    # 检查是否已存在配置
    if grep -q "文件描述符限制 (auto-configured)" "$LIMITS_CONF"; then
        log_warning "检测到已存在的文件描述符配置，将跳过重复配置"
        return 0
    fi
    
    cat >> "$LIMITS_CONF" << 'EOF'

# ===== 文件描述符限制 v1.0.0 =====
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576

# 进程数限制
* soft nproc 65536
* hard nproc 65536
root soft nproc 65536
root hard nproc 65536
# ================================================
EOF
    
    log_success "文件描述符限制配置已添加"
}

# 应用配置并验证
apply_and_verify_config() {
    # 先测试配置的有效性，过滤掉无效参数
    local temp_output
    temp_output=$(sysctl -p 2>&1)
    local sysctl_exit_code=$?
    
    if [[ $sysctl_exit_code -eq 0 ]]; then
        log_success "sysctl 配置应用成功"
    else
        # 检查是否只是conntrack相关的错误
        if echo "$temp_output" | grep -q "nf_conntrack_max.*No such file or directory"; then
            log_warning "检测到 conntrack 模块未加载，跳过相关参数"
            
            # 创建临时配置文件，过滤掉conntrack参数
            local temp_sysctl="/tmp/sysctl_filtered.conf"
            grep -v "nf_conntrack_max" "$SYSCTL_CONF" > "$temp_sysctl"
            
            # 尝试应用过滤后的配置
            if sysctl -p "$temp_sysctl" >/dev/null 2>&1; then
                log_success "sysctl 配置应用成功（已跳过无效参数）"
                # 更新原配置文件，移除无效参数
                cp "$temp_sysctl" "$SYSCTL_CONF"
                log_info "已从配置文件中移除无效的 conntrack 参数"
            else
                log_error "sysctl 配置应用失败，检查详细错误..."
                sysctl -p "$temp_sysctl"
                rm -f "$temp_sysctl"
                return 1
            fi
            rm -f "$temp_sysctl"
        else
            # 其他类型的错误
            log_error "sysctl 配置应用失败，检查详细错误..."
            echo "$temp_output" >&2
            return 1
        fi
    fi
    
    # 立即应用ulimit
    if ulimit -n 1048576 2>/dev/null; then
        log_success "文件描述符限制应用成功"
    else
        log_warning "文件描述符限制应用失败，重启后生效"
    fi
}

# 配置防火墙规则
configure_firewall() {
    log_step "配置防火墙规则..."
    
    # 检查并配置ufw
    if command -v ufw >/dev/null 2>&1; then
        log_info "检测到 ufw 防火墙"
        if ufw --force enable >/dev/null 2>&1; then
            # 允许高端口范围以支持更多并发连接
            if ufw allow 10000:65535/tcp >/dev/null 2>&1; then
                log_success "ufw 规则配置成功"
            else
                log_warning "ufw 规则配置失败"
            fi
        else
            log_warning "无法启用ufw防火墙"
        fi
    # 检查并配置iptables
    elif command -v iptables >/dev/null 2>&1; then
        log_info "检测到 iptables 防火墙"
        # 为iptables添加基本规则（示例）
        if iptables -L INPUT -n | grep -q "tcp dpts:10000:65535" 2>/dev/null; then
            log_info "iptables 规则已存在"
        else
            log_info "建议手动配置 iptables 规则以允许高端口连接"
        fi
    else
        log_warning "未检测到支持的防火墙系统[跳过]"
    fi
}

# 显示优化结果
show_optimization_results() {
    log_step "显示优化结果..."
    
    echo
    echo "=== 🚀 TCP优化配置完成 ==="
    
    # 显示当前拥塞控制算法
    if command -v sysctl >/dev/null 2>&1; then
        echo "拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
        echo "TCP快速打开: $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo '未知')"
        echo "队列调度算法: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo '未知')"
    fi
    
    echo "当前文件描述符限制: $(ulimit -n)"
    
    # 检查BBR状态
    if lsmod | grep -q bbr 2>/dev/null; then
        log_success "BBR模块已激活"
    else
        log_warning "BBR模块未激活（可能需要重启或手动加载）"
    fi
    
    echo "=========================="
}

# 显示后续建议
show_recommendations() {
    echo
    echo "=== 📋 优化后建议 ==="
    echo "1. 重启系统以确保所有优化完全生效"
    echo "2. 监控系统性能和网络连接状态"
    echo "3. 如需回滚，使用备份文件: $BACKUP_DIR"
    echo "====================="
}

# 错误处理和回滚
rollback_changes() {
    log_error "检测到错误，正在回滚更改..."
    
    if [[ -d "$BACKUP_DIR" ]]; then
        if [[ -f "$BACKUP_DIR/sysctl.conf.bak" ]]; then
            cp "$BACKUP_DIR/sysctl.conf.bak" "$SYSCTL_CONF"
            log_info "已恢复sysctl配置"
        fi
        
        if [[ -f "$BACKUP_DIR/limits.conf.bak" ]]; then
            cp "$BACKUP_DIR/limits.conf.bak" "$LIMITS_CONF"
            log_info "已恢复limits配置"
        fi
        
        # 重新加载配置
        sysctl -p >/dev/null 2>&1 || true
        log_info "配置已回滚到优化前状态"
    fi
}

# 主程序
main() {
    echo
    
    # 1. 检查root权限
    if [[ $(id -u) -ne 0 ]]; then
        log_error "此脚本必须使用 root 权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
    
    # 2. 系统兼容性检查
    check_system_compatibility
    
    # 3. 内核版本检查
    check_kernel_version "$MIN_KERNEL_VERSION" || log_warning "建议升级内核以获得最佳性能"
    
    # 4. 创建备份
    create_backup
    
    # 5. 设置错误处理
    trap rollback_changes ERR
    
    # 6. 应用TCP优化
    apply_tcp_optimization
    
    # 7. 应用文件描述符优化
    apply_ulimit_optimization
    
    # 8. 应用配置
    apply_and_verify_config
    
    # 9. 配置防火墙
    configure_firewall
    
    # 10. 显示结果
    show_optimization_results
    
    # 11. 显示建议
    show_recommendations
    
    # 清除错误陷阱
    trap - ERR
    
    log_success "TCP网络调优完成！"
    echo
}

# 执行主程序
main "$@"
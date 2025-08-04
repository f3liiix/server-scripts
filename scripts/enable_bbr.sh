#!/bin/bash

# ==============================================================================
# Script Name: enable_bbr.sh
# Description: Enhanced BBR (Bottleneck Bandwidth and RTT) enablement script
#              Based on teddysun's BBR script with improvements and integration
# Original:    https://raw.githubusercontent.com/teddysun/across/master/bbr.sh
# Author:      Optimized version (based on teddysun's work)
# Date:        2025-01-08
# Version:     2.0
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
readonly SCRIPT_VERSION="2.0"
readonly BACKUP_DIR="/etc/backup_bbr_$(date +%Y%m%d_%H%M%S)"
readonly SYSCTL_CONF="/etc/sysctl.conf"
readonly MIN_KERNEL_VERSION="4.9"
readonly LOG_FILE="/var/log/bbr_installation.log"

# BBR内核下载源配置
readonly UBUNTU_KERNEL_BASE="https://kernel.ubuntu.com/~kernel-ppa/mainline"
readonly CENTOS6_KERNEL_BASE="https://dl.lamp.sh/files"
readonly CENTOS7_KERNEL_BASE="https://dl.lamp.sh/kernel/el7"

# --- BBR专用函数 ---

# 检查BBR是否已启用
check_bbr_status() {
    local current_cc
    if [[ -f /proc/sys/net/ipv4/tcp_congestion_control ]]; then
        current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
        [[ "$current_cc" == "bbr" ]]
    else
        return 1
    fi
}

# 检查BBR是否可用
check_bbr_available() {
    if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
    else
        return 1
    fi
}

# 检查内核是否支持BBR
check_kernel_bbr_support() {
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)
    version_compare "$kernel_version" "$MIN_KERNEL_VERSION"
}

# 检查虚拟化环境
check_virtualization() {
    log_step "检查虚拟化环境..."
    
    local virt=""
    if command_exists "virt-what"; then
        virt=$(virt-what 2>/dev/null || echo "")
    elif command_exists "systemd-detect-virt"; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "")
    fi
    
    case "$virt" in
        "lxc")
            log_error "不支持LXC虚拟化环境"
            return 1
            ;;
        "openvz")
            log_error "不支持OpenVZ虚拟化环境"
            return 1
            ;;
        "")
            log_info "物理机或支持的虚拟化环境"
            ;;
        *)
            log_info "检测到虚拟化环境: $virt"
            ;;
    esac
    
    # 检查OpenVZ特征目录
    if [[ -d "/proc/vz" ]]; then
        log_error "检测到OpenVZ环境，不支持内核升级"
        return 1
    fi
    
    return 0
}

# 获取系统架构信息
get_system_arch() {
    local arch
    arch=$(uname -m)
    
    # 标准化架构名称
    case "$arch" in
        "x86_64"|"amd64")
            echo "x86_64"
            ;;
        "i386"|"i686")
            echo "i386"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            return 1
            ;;
    esac
}

# 检查系统是否为64位
is_64bit() {
    [[ $(getconf WORD_BIT) = '32' ]] && [[ $(getconf LONG_BIT) = '64' ]]
}

# 获取最新内核版本列表
get_latest_kernel_versions() {
    log_info "获取最新内核版本列表..."
    
    local versions
    if ! versions=$(wget -qO- "$UBUNTU_KERNEL_BASE/" 2>/dev/null | \
        awk -F'"v' '/v[4-9]./{print $2}' | \
        cut -d/ -f1 | \
        grep -v - | \
        sort -V); then
        log_error "获取内核版本列表失败"
        return 1
    fi
    
    # 过滤出5.15+版本（推荐版本）
    local recommended_versions=()
    while IFS= read -r version; do
        if [[ -n "$version" ]] && version_compare "$version" "5.15"; then
            recommended_versions+=("$version")
        fi
    done <<< "$versions"
    
    if [[ ${#recommended_versions[@]} -eq 0 ]]; then
        log_error "未找到合适的内核版本"
        return 1
    fi
    
    # 返回最新的几个版本
    printf '%s\n' "${recommended_versions[@]}" | tail -10
}

# 选择内核版本
select_kernel_version() {
    local versions
    if ! versions=$(get_latest_kernel_versions); then
        return 1
    fi
    
    local version_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && version_array+=("$line")
    done <<< "$versions"
    
    if [[ ${#version_array[@]} -eq 0 ]]; then
        log_error "没有可用的内核版本"
        return 1
    fi
    
    echo
    echo "=== 可用的内核版本 ==="
    for i in "${!version_array[@]}"; do
        local idx=$((i + 1))
        printf "%2d) %s\n" "$idx" "${version_array[$i]}"
    done
    echo "========================"
    
    local choice
    local max_choice=${#version_array[@]}
    
    while true; do
        read -p "请选择内核版本 (1-$max_choice, 回车选择最新版): " choice
        
        # 默认选择最新版本
        if [[ -z "$choice" ]]; then
            choice=$max_choice
            break
        fi
        
        # 验证输入
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max_choice" ]]; then
            break
        else
            log_warning "请输入 1-$max_choice 之间的数字"
        fi
    done
    
    local selected_version="${version_array[$((choice - 1))]}"
    log_info "选择的内核版本: $selected_version"
    echo "$selected_version"
}

# 下载并安装Debian/Ubuntu内核
install_debian_kernel() {
    local kernel_version="$1"
    local arch
    
    if ! arch=$(get_system_arch); then
        return 1
    fi
    
    log_info "下载并安装内核 $kernel_version (架构: $arch)..."
    
    # 构建下载URL
    local base_url="$UBUNTU_KERNEL_BASE/v${kernel_version}"
    local arch_suffix
    
    if [[ "$arch" == "x86_64" ]]; then
        arch_suffix="amd64"
    else
        arch_suffix="i386"
    fi
    
    # 获取文件名
    local kernel_image_name
    local kernel_modules_name
    
    if ! kernel_image_name=$(wget -qO- "$base_url/" | \
        grep "linux-image" | grep "generic" | \
        awk -F'">' "/\\.${arch_suffix}\\.deb/{print \$2}" | \
        cut -d'<' -f1 | head -1); then
        log_error "获取内核镜像文件名失败"
        return 1
    fi
    
    if ! kernel_modules_name=$(wget -qO- "$base_url/" | \
        grep "linux-modules" | grep "generic" | \
        awk -F'">' "/\\.${arch_suffix}\\.deb/{print \$2}" | \
        cut -d'<' -f1 | head -1); then
        log_warning "获取内核模块文件名失败，尝试继续安装"
    fi
    
    if [[ -z "$kernel_image_name" ]]; then
        log_error "内核镜像文件名为空"
        return 1
    fi
    
    # 下载文件
    local image_url="$base_url/$kernel_image_name"
    local modules_url="$base_url/$kernel_modules_name"
    
    log_info "下载内核镜像: $kernel_image_name"
    if ! wget -c -t3 -T60 -O "$kernel_image_name" "$image_url"; then
        log_error "下载内核镜像失败"
        return 1
    fi
    
    local install_files=("$kernel_image_name")
    
    if [[ -n "$kernel_modules_name" ]]; then
        log_info "下载内核模块: $kernel_modules_name"
        if wget -c -t3 -T60 -O "$kernel_modules_name" "$modules_url"; then
            install_files+=("$kernel_modules_name")
        else
            log_warning "下载内核模块失败，继续安装"
        fi
    fi
    
    # 安装内核包
    log_info "安装内核包..."
    if ! dpkg -i "${install_files[@]}"; then
        log_error "安装内核包失败"
        # 清理下载的文件
        rm -f "${install_files[@]}"
        return 1
    fi
    
    # 清理下载的文件
    rm -f "${install_files[@]}"
    
    # 更新GRUB
    log_info "更新GRUB配置..."
    if ! /usr/sbin/update-grub; then
        log_error "更新GRUB失败"
        return 1
    fi
    
    log_success "内核安装完成"
    return 0
}

# 下载并安装CentOS内核
install_centos_kernel() {
    local os_version
    os_version=$(detect_system | cut -d: -f2 | cut -d. -f1)
    
    log_info "安装CentOS $os_version 内核..."
    
    # 检查perl依赖
    if ! command_exists perl; then
        log_info "安装perl依赖..."
        yum install -y perl
    fi
    
    local kernel_base_url
    local kernel_name
    local kernel_devel_name
    
    case "$os_version" in
        "6")
            kernel_base_url="$CENTOS6_KERNEL_BASE"
            if is_64bit; then
                kernel_name="kernel-ml-4.18.20-1.el6.elrepo.x86_64.rpm"
                kernel_devel_name="kernel-ml-devel-4.18.20-1.el6.elrepo.x86_64.rpm"
            else
                kernel_name="kernel-ml-4.18.20-1.el6.elrepo.i686.rpm"
                kernel_devel_name="kernel-ml-devel-4.18.20-1.el6.elrepo.i686.rpm"
            fi
            ;;
        "7")
            kernel_base_url="$CENTOS7_KERNEL_BASE"
            if is_64bit; then
                kernel_name="kernel-ml-5.15.60-1.el7.x86_64.rpm"
                kernel_devel_name="kernel-ml-devel-5.15.60-1.el7.x86_64.rpm"
            else
                log_error "CentOS 7 不支持32位架构"
                return 1
            fi
            ;;
        *)
            log_error "不支持的CentOS版本: $os_version"
            return 1
            ;;
    esac
    
    # 导入GPG密钥 (CentOS 6)
    if [[ "$os_version" == "6" ]]; then
        log_info "导入ELRepo GPG密钥..."
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    fi
    
    # 下载内核包
    log_info "下载内核包: $kernel_name"
    if ! wget -c -t3 -T60 -O "$kernel_name" "$kernel_base_url/$kernel_name"; then
        log_error "下载内核包失败"
        return 1
    fi
    
    log_info "下载内核开发包: $kernel_devel_name"
    if ! wget -c -t3 -T60 -O "$kernel_devel_name" "$kernel_base_url/$kernel_devel_name"; then
        log_error "下载内核开发包失败"
        rm -f "$kernel_name"
        return 1
    fi
    
    # 安装内核包
    log_info "安装内核包..."
    if ! rpm -ivh "$kernel_name"; then
        log_error "安装内核包失败"
        rm -f "$kernel_name" "$kernel_devel_name"
        return 1
    fi
    
    if ! rpm -ivh "$kernel_devel_name"; then
        log_error "安装内核开发包失败"
        rm -f "$kernel_name" "$kernel_devel_name"
        return 1
    fi
    
    # 清理下载的文件
    rm -f "$kernel_name" "$kernel_devel_name"
    
    # 设置默认启动内核
    if [[ "$os_version" == "6" ]]; then
        if [[ -f "/boot/grub/grub.conf" ]]; then
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
            log_info "已设置新内核为默认启动项"
        else
            log_error "/boot/grub/grub.conf 不存在"
            return 1
        fi
    elif [[ "$os_version" == "7" ]]; then
        /usr/sbin/grub2-set-default 0
        log_info "已设置新内核为默认启动项"
    fi
    
    log_success "内核安装完成"
    return 0
}

# 安装支持BBR的内核
install_bbr_kernel() {
    log_step "安装支持BBR的内核..."
    
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    
    case "$distro" in
        "ubuntu"|"debian")
            local kernel_version
            if kernel_version=$(select_kernel_version); then
                install_debian_kernel "$kernel_version"
            else
                return 1
            fi
            ;;
        "centos")
            install_centos_kernel
            ;;
        *)
            log_error "不支持的发行版: $distro"
            return 1
            ;;
    esac
}

# 配置BBR
configure_bbr() {
    log_step "配置BBR参数..."
    
    # 创建备份
    if [[ -f "$SYSCTL_CONF" ]]; then
        local backup_file="${SYSCTL_CONF}.bbr_backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SYSCTL_CONF" "$backup_file"
        log_info "已备份配置文件到: $backup_file"
    fi
    
    # 移除旧的BBR配置
    if [[ -f "$SYSCTL_CONF" ]]; then
        sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
    fi
    
    # 添加BBR配置
    {
        echo ""
        echo "# === BBR拥塞控制配置 (enable_bbr.sh v$SCRIPT_VERSION) ==="
        echo "# Generated on: $(date)"
        echo "net.core.default_qdisc = fq"
        echo "net.ipv4.tcp_congestion_control = bbr"
        echo "# =============================================="
    } >> "$SYSCTL_CONF"
    
    # 应用配置
    log_info "应用BBR配置..."
    if sysctl -p >/dev/null 2>&1; then
        log_success "BBR配置应用成功"
    else
        log_error "BBR配置应用失败"
        return 1
    fi
    
    return 0
}

# 验证BBR状态
verify_bbr_status() {
    log_step "验证BBR状态..."
    
    # 检查BBR是否启用
    if check_bbr_status; then
        log_success "✅ BBR已成功启用"
        
        # 显示详细信息
        echo
        echo "=== BBR状态详情 ==="
        echo "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
        echo "队列调度算法: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo '未知')"
        echo "可用拥塞控制: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '未知')"
        
        # 检查BBR模块是否加载
        if lsmod | grep -q bbr 2>/dev/null; then
            echo "BBR模块状态: ✅ 已加载"
        else
            echo "BBR模块状态: ⚠️ 未检测到模块（可能内置）"
        fi
        echo "=================="
        
        return 0
    else
        log_error "❌ BBR启用验证失败"
        return 1
    fi
}

# 显示后续建议
show_bbr_recommendations() {
    echo
    echo "=== 📋 BBR启用后建议 ==="
    echo "1. 重启系统以确保BBR完全生效（如果安装了新内核）"
    echo "2. 监控网络性能变化，BBR通常能提升15-25%的吞吐量"
    echo "3. 使用以下命令验证BBR状态:"
    echo "   sysctl net.ipv4.tcp_congestion_control"
    echo "   lsmod | grep bbr"
    echo "4. 进行网络性能测试对比优化效果"
    echo "5. 如遇问题，可通过备份文件恢复配置"
    echo "======================="
}

# 询问是否重启系统
prompt_reboot() {
    echo
    log_warning "安装了新内核，建议重启系统以启用BBR"
    
    if confirm_action "是否立即重启系统？" "N"; then
        log_info "正在重启系统..."
        sleep 2
        reboot
    else
        log_info "重启已取消，请手动重启系统以启用新内核"
        echo
        echo "重启后，请运行以下命令验证BBR状态:"
        echo "  sudo sysctl net.ipv4.tcp_congestion_control"
        echo "  lsmod | grep bbr"
    fi
}

# 显示系统信息
show_system_info() {
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    local version="${system_info#*:}"
    
    echo "=== 系统信息 ==="
    echo "操作系统: $distro $version"
    echo "内核版本: $(uname -r)"
    echo "系统架构: $(uname -m) ($(getconf LONG_BIT)位)"
    echo "==============="
}

# 主程序
main() {
    echo "=== BBR启用脚本 v$SCRIPT_VERSION ==="
    echo
    
    # 1. 权限检查
    if ! check_root; then
        exit 1
    fi
    
    # 2. 显示系统信息
    show_system_info
    
    # 3. 检查虚拟化环境
    if ! check_virtualization; then
        exit 1
    fi
    
    # 4. 检查系统兼容性
    if ! is_debian_based; then
        local system_info
        system_info=$(detect_system)
        local distro="${system_info%:*}"
        
        if [[ "$distro" != "centos" ]]; then
            log_error "不支持的操作系统，仅支持 Debian、Ubuntu 和 CentOS"
            exit 1
        fi
    fi
    
    # 5. 检查BBR当前状态
    if check_bbr_status; then
        log_success "BBR已经启用，无需重复配置"
        verify_bbr_status
        exit 0
    fi
    
    # 6. 检查内核版本
    local kernel_upgrade_needed=false
    if check_kernel_bbr_support; then
        log_success "当前内核版本支持BBR"
        
        # 检查BBR是否可用
        if check_bbr_available; then
            log_info "BBR模块可用，直接配置启用"
        else
            log_warning "BBR模块不可用，但内核版本支持，尝试配置"
        fi
    else
        log_warning "当前内核版本不支持BBR，需要升级内核"
        kernel_upgrade_needed=true
        
        # 用户确认
        if ! confirm_action "是否继续安装新内核以支持BBR？" "Y"; then
            log_info "用户取消了内核升级"
            exit 0
        fi
    fi
    
    # 7. 安装内核（如果需要）
    if [[ "$kernel_upgrade_needed" == true ]]; then
        if ! install_bbr_kernel; then
            log_error "内核安装失败"
            exit 1
        fi
    fi
    
    # 8. 配置BBR
    if ! configure_bbr; then
        log_error "BBR配置失败"
        exit 1
    fi
    
    # 9. 验证BBR状态
    if verify_bbr_status; then
        show_bbr_recommendations
        
        # 如果安装了新内核，询问是否重启
        if [[ "$kernel_upgrade_needed" == true ]]; then
            prompt_reboot
        fi
        
        log_success "BBR启用完成！"
    else
        if [[ "$kernel_upgrade_needed" == true ]]; then
            log_info "新内核已安装，BBR将在重启后生效"
            prompt_reboot
        else
            log_error "BBR启用失败，请检查系统日志"
            exit 1
        fi
    fi
}

# 执行主程序
main "$@"
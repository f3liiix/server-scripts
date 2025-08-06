#!/bin/bash

# ==============================================================================
# Script Name: install_bt.sh
# Description: Install Baota Panel happy version
# Author:      f3liiix
# Date:        2025-08-07
# Version:     1.0.0
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

# 检查root权限
check_root || exit 1

# 宝塔面板安装选项菜单
show_bt_menu() {
    echo
    echo -e "${CYAN}🔸 请选择操作${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}1${NC} ▶ 📦 安装宝塔面板 11.0.0 开心版${GRAY}（支持 Debian/Ubuntu/CentOS 等系统）${NC}"
    echo -e "  ${CYAN}2${NC} ▶ 🔄 升级宝塔面板至 11.0.0 开心版${GRAY}（支持所有版本升级至开心版）${NC}"
    echo -e "  ${DARK_GRAY}───────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}0${NC} ▶ 🚪 退出"
    echo
}

# 安装宝塔面板 11.0.0 开心版
install_bt() {
    log_step "正在安装宝塔面板 11.0.0 开心版..."
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    # 检查系统支持
    local system_info
    system_info=$(detect_system)
    local distro="${system_info%:*}"
    
    case "$distro" in
        "centos"|"debian"|"ubuntu"|"fedora")
            log_info "检测到支持的系统: $distro"
            ;;
        *)
            log_warning "系统 $distro 可能不受支持，继续安装..."
            ;;
    esac
    
    # 执行安装命令
    if [ -f /usr/bin/curl ]; then
        curl -sSO https://io.bt.sb/install/install_latest.sh
    else
        wget -O install_latest.sh https://io.bt.sb/install/install_latest.sh
    fi
    
    if [[ -f "install_latest.sh" ]]; then
        bash install_latest.sh
        rm -rf install_latest.sh
        log_success "宝塔面板安装完成"
    else
        log_error "下载安装脚本失败"
        return 1
    fi
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
}

# 升级宝塔面板至 11.0.0 开心版
update_bt() {
    log_step "正在升级宝塔面板至 11.0.0 开心版..."
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    # 执行升级命令
    if command_exists curl; then
        curl https://io.bt.sb/install/update_panel.sh | bash -s -- 11.0.0
        log_success "宝塔面板升级完成"
    else
        log_error "系统缺少 curl 命令，请先安装 curl"
        return 1
    fi
    
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
}

# 主程序
main() {
    while true; do
        show_bt_menu
        read -p "$(echo -e "${YELLOW}请输入选择 (1-2, 0): ${NC}")" choice
        
        case $choice in
            1)
                echo
                echo -e "${CYAN}▶▶▶ 正在执行 [安装宝塔面板 11.0.0 开心版]${NC}"
                install_bt
                echo
                echo -e "${CYAN}按任意键返回宝塔面板菜单...${NC}"
                read -n 1 -s
                echo
                ;;
            2)
                echo
                echo -e "${CYAN}▶▶▶ 正在执行 [升级宝塔面板至 11.0.0 开心版]${NC}"
                if ! update_bt; then
                    log_error "升级过程出现错误"
                fi
                echo
                echo -e "${CYAN}按任意键返回宝塔面板菜单...${NC}"
                read -n 1 -s
                echo
                ;;
            0)
                return 0
                ;;
            *)
                echo
                log_warning "无效选择，请输入 0-2 之间的数字"
                echo
                sleep 2
                ;;
        esac
    done
}

# 执行主程序
main "$@"
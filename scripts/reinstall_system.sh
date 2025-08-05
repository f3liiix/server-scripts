#!/bin/bash

# 一键dd纯净系统(萌咖)脚本
# 集成到 server-scripts 项目中

# 引入通用函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

# 颜色定义（使用 common_functions.sh 中的定义）
# 检查 wget 是否安装
check_wget() {
    if ! command -v wget &> /dev/null; then
        echo -e "${INFO} wget 未安装，正在安装..."
        if command -v apt &> /dev/null; then
            apt update && apt install -y wget
        elif command -v yum &> /dev/null; then
            yum install -y wget
        else
            echo -e "${ERROR} 无法识别的包管理器，请手动安装 wget"
            return 1
        fi
    fi
}

# 获取用户选择的操作系统
select_os() {
    while true; do
        echo -e "\n${GREEN}💿 请选择要安装的操作系统:${NC}"
        echo
        echo "  1) Debian"
        echo "  2) Ubuntu"
        echo "  3) CentOS"
        echo "  4) Alpine"
        echo
        read -rp "$(echo -e "${YELLOW}请输入选择 (1-4，默认为 1, Debian): ${NC}")" os_choice
        
        case "${os_choice}" in
            1|'') OS="debian"; break ;;
            2) OS="ubuntu"; break ;;
            3) OS="centos"; break ;;
            4) OS="alpine"; break ;;
            *) echo -e "${ERROR} 无效选择，请输入 1-4 之间的数字" ;;
        esac
    done
}

# 获取用户选择的系统版本
select_version() {
    while true; do
        case "${OS}" in
            "debian")
                echo -e "\n${GREEN}💿 请选择 Debian 版本:${NC}"
                echo
                echo "  1) Debian 11 (bullseye)"
                echo "  2) Debian 12 (bookworm) [默认]"
                echo
                read -rp "$(echo -e "${YELLOW}请输入选择 (1-2，默认为 2, Debian 12): ${NC}")" ver_choice
                
                case "${ver_choice}" in
                    1) VERSION="11"; break ;;
                    ''|2) VERSION="12"; break ;;
                    *) echo -e "${ERROR}无效选择，请输入 1-2 之间的数字" ;;
                esac
                ;;
            "ubuntu")
                echo -e "\n${GREEN}💿 请选择 Ubuntu 版本:${NC}"
                echo
                echo "  1) Ubuntu 20.04 (focal)"
                echo "  2) Ubuntu 22.04 (jammy)"
                echo "  3) Ubuntu 24.04 (noble) [默认]"
                echo
                read -rp "$(echo -e "${YELLOW}请输入选择 (1-3，默认为 3, Ubuntu 24.04): ${NC}")" ver_choice
                
                case "${ver_choice}" in
                    1) VERSION="20.04"; break ;;
                    2) VERSION="22.04"; break ;;
                    ''|3) VERSION="24.04"; break ;;
                    *) echo -e "${ERROR}无效选择，请输入 1-3 之间的数字" ;;
                esac
                ;;
            "centos")
                echo -e "\n${GREEN}💿 请选择 CentOS 版本:${NC}"
                echo
                echo "  1) CentOS 7"
                echo "  2) CentOS 8 [默认]"
                echo "  3) CentOS 9"
                echo
                read -rp "$(echo -e "${YELLOW}请输入选择 (1-3，默认为 2, CentOS 8): ${NC}")" ver_choice
                
                case "${ver_choice}" in
                    1) VERSION="7"; break ;;
                    ''|2) VERSION="8"; break ;;
                    3) VERSION="9"; break ;;
                    *) echo -e "${ERROR}无效选择，请输入 1-3 之间的数字" ;;
                esac
                ;;
            "alpine")
                echo -e "\n${GREEN}💿 请选择 Alpine 版本:${NC}"
                echo
                echo "  1) Alpine 3.16"
                echo "  2) Alpine 3.17"
                echo "  3) Alpine 3.18"
                echo "  4) Alpine edge [默认]"
                echo
                read -rp "$(echo -e "${YELLOW}请输入选择 (1-4，默认为 4, Alpine edge): ${NC}")" ver_choice
                
                case "${ver_choice}" in
                    1) VERSION="3.16"; break ;;
                    2) VERSION="3.17"; break ;;
                    3) VERSION="3.18"; break ;;
                    ''|4) VERSION="edge"; break ;;
                    *) echo -e "${ERROR}无效选择，请输入 1-4 之间的数字" ;;
                esac
                ;;
        esac
    done
}

# 获取 SSH 端口
get_ssh_port() {
    while true; do
        read -rp "$(echo -e "\n${INFO}🔐 请输入 SSH 端口 (默认为 22): ${YELLOW}")" port_input
        echo -ne "${NC}"
        
        # 如果用户直接按回车，使用默认值
        if [[ -z "${port_input}" ]]; then
            SSH_PORT="22"
            break
        fi
        
        # 检查输入是否为数字且在有效范围内，并避免使用 80 和 443 端口
        if [[ "${port_input}" =~ ^[0-9]+$ ]] && [ "${port_input}" -ge 1 ] && [ "${port_input}" -le 65535 ]; then
            if [ "${port_input}" -eq 80 ] || [ "${port_input}" -eq 443 ]; then
                echo -e "${ERROR}端口 80 和 443 是常用 Web 服务端口，请选择其他端口"
            else
                SSH_PORT="${port_input}"
                break
            fi
        else
            echo -e "${ERROR}端口号必须是 1-65535 之间的数字，请重新输入"
        fi
    done
}

# 获取 SSH 密码
get_ssh_password() {
    while true; do
        echo -ne "\n${INFO}🔐 请输入 SSH 密码 (默认密码为 12345678): ${YELLOW}"
        read -rsp "" SSH_PASSWORD
        echo -ne "${NC}"
        
        # 如果用户直接按回车，使用默认密码
        if [[ -z "${SSH_PASSWORD}" ]]; then
            SSH_PASSWORD="12345678"
            echo  # 换行
            break
        fi
        
        echo  # 换行
        echo -ne "${INFO}🔐 请再次输入 SSH 密码以确认: ${YELLOW}"
        read -rsp "" SSH_PASSWORD_CONFIRM
        echo -ne "${NC}"
        echo  # 换行
        
        # 检查两次输入是否一致
        if [[ "${SSH_PASSWORD}" == "${SSH_PASSWORD_CONFIRM}" ]]; then
            break
        else
            echo -e "${ERROR}两次输入的密码不一致，请重新输入"
        fi
    done
}

# 获取主机名
get_hostname() {
    read -rp "$(echo -e "\n${INFO}🔤 请输入主机名 (默认为 ${OS}): ${YELLOW}")" CUSTOM_HOSTNAME
    echo -ne "${NC}"
    if [[ -z "${CUSTOM_HOSTNAME}" ]]; then
        HOSTNAME="${OS}"
    else
        HOSTNAME="${CUSTOM_HOSTNAME}"
    fi
}

# 是否启用 BBR
enable_bbr_option() {
    read -rp "$(echo -e "\n${INFO}🚀 是否启用 BBR? (Y/n): ${YELLOW}")" bbr_choice
    echo -ne "${NC}"
    case "${bbr_choice}" in
        n|N) ENABLE_BBR=false ;;
        *) ENABLE_BBR=true ;;
    esac
}

# 下载并执行脚本
run_reinstall() {
    echo -e "\n${INFO}⬇️  开始下载安装脚本..."
    
    if ! check_wget; then
        echo -e "${ERROR}wget 安装失败，无法继续"
        return 1
    fi
    
    # 下载脚本
    if ! wget --no-check-certificate -qO InstallNET.sh 'https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh'; then
        echo -e "${ERROR}下载 InstallNET.sh 脚本失败"
        return 1
    fi
    
    # 添加执行权限
    chmod a+x InstallNET.sh
    
    echo -e "${INFO}☑️  脚本下载完成，准备执行..."
    
    # 构建命令
    CMD="bash InstallNET.sh -${OS} ${VERSION} -port \"${SSH_PORT}\" -pwd '${SSH_PASSWORD}' -hostname \"${HOSTNAME}\""
    
    if [[ "${ENABLE_BBR}" == true ]]; then
        CMD="${CMD} --bbr"
    fi
    
    echo -e "\n${INFO}ℹ️  将执行以下命令:"
    echo "${CMD}"
    
    # 展示重装后的 SSH 登录信息
    echo -e "\n${CYAN}📋 重装后 SSH 登录信息:${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}端口：${SSH_PORT}${NC}"
    echo -e "${GREEN}用户：root${NC}"
    echo -e "${GREEN}密码：${SSH_PASSWORD}${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"

    echo -e "\n${WARN}${YELLOW}⚠️ 重要提醒:${NC}"
    echo "1. 系统重装后所有数据将丢失，请提前做好数据备份"
    echo "2. 脚本执行完毕后需使用 reboot 命令重启开始重装"
    echo "3. 请确认你的服务器安全组已放行 SSH 端口 ${SSH_PORT}"
    
    read -rp "$(echo -e "\n${CONFIRM}${YELLOW}确认执行? (Y/n): ${NC}")" confirm
    
    if [[ "${confirm}" =~ ^[Nn]$ ]]; then
        echo -e "\n${INFO}已取消操作"
        rm -f InstallNET.sh
        return 0
    else
        echo -e "\n${INFO}${CYAN}开始运行重装脚本...${NC}"
        # 执行重装命令，但不直接使用 eval
        # 这样可以避免当前 shell 被第三方脚本退出影响
        bash InstallNET.sh -${OS} ${VERSION} -port "${SSH_PORT}" -pwd '${SSH_PASSWORD}' -hostname "${HOSTNAME}" ${ENABLE_BBR:+--bbr}
        
        # 脚本执行成功后删除临时文件
        rm -f InstallNET.sh
        
        # 显示执行完成信息
        echo -e "\n${INFO}✅ 系统重装脚本已执行完成（重启后需等待新系统安装完成才可连接SSH，大约 5-10 分钟）"
        
        # 询问是否立即重启
        read -rp "$(echo -e "\n${CONFIRM}${YELLOW}是否立即重启系统? (Y/n): ${NC}")" restart_confirm
        
        if [[ ! "${restart_confirm}" =~ ^[Nn]$ ]]; then
            echo -e "\n${INFO}🔄 正在重启系统..."
            sleep 3
            # 使用 nohup 和 & 让重启命令在后台执行，确保脚本正常返回
            nohup bash -c 'sleep 1 && reboot' > /dev/null 2>&1 &
        else
            echo -e "\n${INFO}ℹ️  您已选择手动重启，请稍后手动执行 'reboot' 命令"
        fi
        
        # 总是返回成功，避免 run_optimization.sh 报错
        return 0
    fi
}

# 主函数
main() {
    
    select_os
    select_version
    
    # 展示用户的选择
    echo -e "\n${INFO}📋 您的选择: ${WHITE}${OS} ${VERSION}${NC}"
    echo -e "${DARK_GRAY}─────────────────────────────────────────────────────────────────${NC}"
    
    get_ssh_port
    get_ssh_password
    get_hostname
    enable_bbr_option
    
    run_reinstall
}

# 执行主函数
main "$@"
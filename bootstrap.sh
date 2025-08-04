#!/bin/bash

# ==============================================================================
# Script Name: bootstrap.sh
# Description: 服务器优化工具集合一键安装脚本
# Author:      Server Optimization Tools
# Date:        2025-01-08
# Version:     1.0
# Usage:       bash <(curl -sL https://raw.githubusercontent.com/user/repo/main/bootstrap.sh)
# ==============================================================================

set -euo pipefail

# --- 配置项 ---
readonly SCRIPT_VERSION="1.0"
readonly TOOLS_NAME="服务器优化工具集合"
readonly INSTALL_DIR="/opt/server-optimization"
readonly TEMP_DIR="/tmp/server-optimization-$$"
readonly LOG_FILE="/var/log/server-optimization-install.log"

# GitHub仓库信息 (使用自定义域名)
readonly REPO_URL="https://github.com/f3liiix/server-scripts"
readonly RAW_URL="https://ss.hide.ss"

# 脚本文件列表
readonly SCRIPT_FILES=(
    "scripts/disable_ipv6.sh"
    "scripts/tcp_tuning.sh" 
    "scripts/enable_bbr.sh"
    "scripts/configure_ssh.sh"
    "scripts/configure_dns.sh"
    "scripts/common_functions.sh"
    "scripts/run_optimization.sh"
    "install.sh"
    "README.md"
)

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# --- 日志函数 ---
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_step() {
    local message="$1"
    echo -e "${CYAN}[STEP]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# --- 辅助函数 ---

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo bash <(curl -sL your-script-url)"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        if command_exists lsb_release; then
            local distro=$(lsb_release -si)
            if [[ "$distro" == "Ubuntu" ]]; then
                echo "ubuntu"
            else
                echo "debian"
            fi
        else
            echo "debian"
        fi
    elif [[ -f /etc/redhat-release ]]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 检查系统兼容性
check_system_compatibility() {
    log_step "检查系统兼容性..."
    
    local os=$(detect_os)
    case "$os" in
        "ubuntu"|"debian")
            log_success "检测到 $(echo "$os" | tr '[:lower:]' '[:upper:]') 系统，完全兼容"
            ;;
        "centos")
            log_warning "检测到 CentOS 系统，部分功能可能需要额外配置"
            ;;
        *)
            log_warning "未知操作系统，可能存在兼容性问题"
            ;;
    esac
    
    # 检查必要命令
    local missing_commands=()
    local required_commands=("curl" "wget" "mkdir" "chmod" "chown")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "缺少必要命令: ${missing_commands[*]}"
        log_info "请先安装这些命令后重试"
        exit 1
    fi
    
    log_success "系统兼容性检查通过"
}

# 创建工作目录
create_directories() {
    log_step "创建工作目录..."
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 创建安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "安装目录已存在: $INSTALL_DIR"
        read -p "是否要覆盖现有安装？(y/N): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi
    
    mkdir -p "$INSTALL_DIR/scripts"
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_success "目录创建完成"
}

# 下载脚本文件
download_scripts() {
    log_step "下载脚本文件..."
    
    local download_count=0
    local total_files=${#SCRIPT_FILES[@]}
    
    for script_file in "${SCRIPT_FILES[@]}"; do
        local url="$RAW_URL/$script_file"
        local local_path="$TEMP_DIR/$script_file"
        local local_dir=$(dirname "$local_path")
        
        # 创建本地目录
        mkdir -p "$local_dir"
        
        log_info "下载: $script_file"
        
        # 尝试使用curl下载
        if command_exists curl; then
            if curl -fsSL "$url" -o "$local_path"; then
                ((download_count++))
                log_success "✅ $script_file"
            else
                log_error "❌ 下载失败: $script_file"
            fi
        # 备用wget下载
        elif command_exists wget; then
            if wget -q "$url" -O "$local_path"; then
                ((download_count++))
                log_success "✅ $script_file"
            else
                log_error "❌ 下载失败: $script_file"
            fi
        else
            log_error "没有可用的下载工具 (curl/wget)"
            exit 1
        fi
    done
    
    if [[ $download_count -eq $total_files ]]; then
        log_success "所有文件下载完成 ($download_count/$total_files)"
    else
        log_error "部分文件下载失败 ($download_count/$total_files)"
        exit 1
    fi
}

# 安装脚本文件
install_scripts() {
    log_step "安装脚本文件..."
    
    # 复制文件到安装目录
    cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
    
    # 设置权限
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    
    # 设置所有者
    chown -R root:root "$INSTALL_DIR"
    
    log_success "脚本文件安装完成"
}

# 创建全局命令链接
create_symlinks() {
    log_step "创建全局命令链接..."
    
    local bin_dir="/usr/local/bin"
    local main_script="$INSTALL_DIR/scripts/run_optimization.sh"
    local global_command="server-optimize"
    
    if [[ -f "$main_script" ]]; then
        # 创建全局命令
        ln -sf "$main_script" "$bin_dir/$global_command"
        
        # 创建各个功能的快捷命令
        cat > "$bin_dir/server-optimize-ipv6" << EOF
#!/bin/bash
exec $main_script ipv6 "\$@"
EOF

        cat > "$bin_dir/server-optimize-tcp" << EOF
#!/bin/bash
exec $main_script tcp "\$@"
EOF

        cat > "$bin_dir/server-optimize-bbr" << EOF
#!/bin/bash
exec $main_script bbr "\$@"
EOF

        cat > "$bin_dir/server-optimize-ssh" << EOF
#!/bin/bash
exec $main_script ssh "\$@"
EOF

        cat > "$bin_dir/server-optimize-dns" << EOF
#!/bin/bash
exec $main_script dns "\$@"
EOF
        
        # 设置权限
        chmod +x "$bin_dir"/server-optimize*
        
        log_success "全局命令创建完成"
        log_info "主命令: $global_command"
        log_info "功能命令: server-optimize-{ipv6|tcp|bbr|ssh|dns}"
    else
        log_warning "主脚本不存在，跳过全局命令创建"
    fi
}

# 运行安装后配置
post_install_setup() {
    log_step "运行安装后配置..."
    
    # 运行原有的install.sh脚本
    local install_script="$INSTALL_DIR/install.sh"
    if [[ -f "$install_script" ]]; then
        cd "$INSTALL_DIR"
        bash "$install_script" --no-links  # 不创建链接，我们已经创建了
        log_success "安装配置完成"
    else
        log_warning "未找到install.sh脚本"
    fi
}

# 清理临时文件
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "清理临时文件完成"
    fi
}

# 显示安装结果
show_install_result() {
    echo
    echo -e "${GREEN}🎉 ${TOOLS_NAME} 安装完成！${NC}"
    echo
    echo -e "${CYAN}安装位置:${NC} $INSTALL_DIR"
    echo -e "${CYAN}日志文件:${NC} $LOG_FILE"
    echo
    echo -e "${WHITE}使用方法:${NC}"
    echo -e "  ${YELLOW}# 查看所有功能${NC}"
    echo -e "  server-optimize --help"
    echo
    echo -e "  ${YELLOW}# 运行单个功能${NC}"
    echo -e "  server-optimize ipv6      # 禁用IPv6"
    echo -e "  server-optimize tcp       # TCP网络优化"
    echo -e "  server-optimize bbr       # 启用BBR算法"
    echo -e "  server-optimize ssh       # SSH安全配置"
    echo -e "  server-optimize dns       # DNS服务器配置"
    echo
    echo -e "  ${YELLOW}# 运行所有优化${NC}"
    echo -e "  server-optimize all"
    echo
    echo -e "  ${YELLOW}# 快捷命令${NC}"
    echo -e "  server-optimize-tcp       # 直接运行TCP优化"
    echo -e "  server-optimize-dns       # 直接运行DNS配置"
    echo
    echo -e "${GREEN}现在您可以开始优化服务器了！${NC}"
    echo
}

# 交互式快速配置
quick_setup() {
    echo
    echo -e "${CYAN}🚀 是否要现在进行快速配置？${NC}"
    echo "1) TCP网络优化"
    echo "2) DNS服务器配置"
    echo "3) SSH安全配置"
    echo "4) 运行所有优化"
    echo "5) 跳过，稍后手动配置"
    echo
    
    read -p "请选择 (1-5): " -r choice
    
    case "$choice" in
        1) server-optimize tcp ;;
        2) server-optimize dns ;;
        3) server-optimize ssh ;;
        4) server-optimize all ;;
        5) log_info "跳过快速配置" ;;
        *) log_warning "无效选择，跳过快速配置" ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
${TOOLS_NAME} 一键安装脚本 v${SCRIPT_VERSION}

用法: bash <(curl -sL your-script-url) [选项]

选项:
  --help          显示此帮助信息
  --install-only  仅安装，不运行快速配置
  --force         强制安装（覆盖现有安装）
  --install-dir DIR  指定安装目录 (默认: ${INSTALL_DIR})

功能:
  - IPv6禁用配置
  - TCP网络性能优化
  - BBR拥塞控制算法启用
  - SSH安全配置
  - DNS服务器配置

安装后使用:
  server-optimize --help    # 查看完整帮助
  server-optimize tcp       # TCP优化
  server-optimize dns       # DNS配置
  server-optimize all       # 全部优化

项目地址: ${REPO_URL}
EOF
}

# 错误处理
error_handler() {
    local exit_code=$?
    log_error "安装过程中发生错误 (退出码: $exit_code)"
    cleanup
    exit $exit_code
}

# 主程序
main() {
    # 设置错误处理
    trap error_handler ERR
    trap cleanup EXIT
    
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                  ${WHITE}${TOOLS_NAME}${PURPLE}                   ║${NC}"
    echo -e "${PURPLE}║                     ${CYAN}一键安装脚本 v${SCRIPT_VERSION}${PURPLE}                      ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # 解析命令行参数
    local install_only=false
    local force_install=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --install-only)
                install_only=true
                shift
                ;;
            --force)
                force_install=true
                shift
                ;;
            --install-dir)
                if [[ -n "${2:-}" ]]; then
                    INSTALL_DIR="$2"
                    shift 2
                else
                    log_error "--install-dir 需要指定目录参数"
                    exit 1
                fi
                ;;
            *)
                log_warning "未知参数: $1"
                shift
                ;;
        esac
    done
    
    # 执行安装步骤
    log_info "开始安装 ${TOOLS_NAME}..."
    
    check_root
    check_system_compatibility
    create_directories
    download_scripts
    install_scripts
    create_symlinks
    post_install_setup
    
    show_install_result
    
    # 快速配置选项
    if [[ "$install_only" == false ]]; then
        quick_setup
    fi
    
    log_success "安装完成！"
}

# 执行主程序
main "$@"
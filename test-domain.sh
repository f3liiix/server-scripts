#!/bin/bash

# ==============================================================================
# Script Name: test-domain.sh
# Description: 测试自定义域名 ss.hide.ss 的配置是否正确
# Usage:       ./test-domain.sh
# ==============================================================================

set -euo pipefail

# --- 配置项 ---
readonly DOMAIN="ss.hide.ss"
readonly TEST_ENDPOINTS=(
    "/"
    "/install"
    "/version"
    "/install.sh"
    "/version.txt"
)

# 颜色定义
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 测试DNS解析
test_dns() {
    log_info "测试DNS解析..."
    
    if command_exists dig; then
        local dns_result=$(dig +short "$DOMAIN")
        if [[ -n "$dns_result" ]]; then
            log_success "DNS解析成功: $DOMAIN → $dns_result"
        else
            log_error "DNS解析失败"
            return 1
        fi
    elif command_exists nslookup; then
        if nslookup "$DOMAIN" >/dev/null 2>&1; then
            log_success "DNS解析成功"
        else
            log_error "DNS解析失败"
            return 1
        fi
    else
        log_warning "未找到dig或nslookup命令，跳过DNS测试"
    fi
}

# 测试HTTPS连接
test_https() {
    log_info "测试HTTPS连接..."
    
    if curl -s --max-time 10 "https://$DOMAIN" >/dev/null; then
        log_success "HTTPS连接成功"
    else
        log_error "HTTPS连接失败"
        return 1
    fi
}

# 测试各个端点
test_endpoints() {
    log_info "测试各个端点..."
    
    local failed_count=0
    
    for endpoint in "${TEST_ENDPOINTS[@]}"; do
        local url="https://$DOMAIN$endpoint"
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" || echo "000")
        
        if [[ "$status_code" == "200" ]]; then
            log_success "✅ $endpoint (HTTP $status_code)"
        else
            log_error "❌ $endpoint (HTTP $status_code)"
            ((failed_count++))
        fi
    done
    
    if [[ $failed_count -eq 0 ]]; then
        log_success "所有端点测试通过"
    else
        log_error "$failed_count 个端点测试失败"
        return 1
    fi
}

# 测试安装脚本内容
test_install_script() {
    log_info "测试直接域名访问的脚本内容..."
    
    # 测试直接访问域名根路径
    local root_content=$(curl -s --max-time 10 "https://$DOMAIN/")
    
    if [[ "$root_content" == *"#!/bin/bash"* ]] && [[ "$root_content" == *"服务器优化工具"* ]]; then
        log_success "✅ 直接域名访问返回脚本内容正确"
    else
        log_error "❌ 直接域名访问脚本内容异常"
        return 1
    fi
    
    # 同时测试/install路径（兼容性）
    local install_content=$(curl -s --max-time 10 "https://$DOMAIN/install")
    
    if [[ "$install_content" == *"#!/bin/bash"* ]] && [[ "$install_content" == *"服务器优化工具"* ]]; then
        log_success "✅ /install 路径访问正常"
    else
        log_warning "⚠️ /install 路径访问异常（不影响主要功能）"
    fi
}

# 测试版本信息
test_version() {
    log_info "测试版本信息..."
    
    local version=$(curl -s --max-time 10 "https://$DOMAIN/version")
    
    if [[ -n "$version" ]] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_success "版本信息正确: $version"
    else
        log_warning "版本信息格式异常: $version"
    fi
}

# 完整功能测试
test_full_functionality() {
    log_info "测试完整功能..."
    
    # 模拟用户安装过程（仅下载测试，不执行）- 直接域名访问
    local install_command="curl -sL https://$DOMAIN/"
    
    if eval "$install_command" | head -5 | grep -q "#!/bin/bash"; then
        log_success "✅ 极简一键安装命令可正常使用"
        log_info "用户可以通过以下命令安装："
        echo -e "  ${YELLOW}bash <(curl -sL $DOMAIN)${NC}"
        echo -e "  ${GREEN}这是目前最简洁的安装方式！${NC}"
    else
        log_error "❌ 极简一键安装命令测试失败"
        return 1
    fi
    
    # 同时测试兼容性路径
    local fallback_command="curl -sL https://$DOMAIN/install"
    if eval "$fallback_command" | head -5 | grep -q "#!/bin/bash"; then
        log_success "✅ 兼容性路径 /install 也可正常使用"
    else
        log_warning "⚠️ 兼容性路径测试失败（不影响主要功能）"
    fi
}

# 性能测试
test_performance() {
    log_info "测试访问性能..."
    
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null --max-time 10 "https://$DOMAIN/")
    local response_time_ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "unknown")
    
    if [[ "$response_time_ms" != "unknown" ]]; then
        if (( $(echo "$response_time < 2.0" | bc -l) )); then
            log_success "响应时间良好: ${response_time_ms%.*}ms"
        else
            log_warning "响应时间较慢: ${response_time_ms%.*}ms"
        fi
    else
        log_warning "无法测试响应时间"
    fi
}

# SSL证书检查
test_ssl_certificate() {
    log_info "检查SSL证书..."
    
    if command_exists openssl; then
        local cert_info=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
        
        if [[ -n "$cert_info" ]]; then
            log_success "SSL证书有效"
            echo "$cert_info" | while read -r line; do
                log_info "  $line"
            done
        else
            log_warning "无法获取SSL证书信息"
        fi
    else
        log_warning "未找到openssl命令，跳过SSL证书检查"
    fi
}

# 主测试函数
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              域名配置测试工具 - $DOMAIN               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    local test_results=()
    
    # 基础连接测试
    if test_dns; then
        test_results+=("DNS解析: ✅")
    else
        test_results+=("DNS解析: ❌")
    fi
    
    if test_https; then
        test_results+=("HTTPS连接: ✅")
    else
        test_results+=("HTTPS连接: ❌")
        log_error "基础连接失败，跳过其他测试"
        return 1
    fi
    
    # 功能测试
    if test_endpoints; then
        test_results+=("端点测试: ✅")
    else
        test_results+=("端点测试: ❌")
    fi
    
    if test_install_script; then
        test_results+=("安装脚本: ✅")
    else
        test_results+=("安装脚本: ❌")
    fi
    
    if test_version; then
        test_results+=("版本信息: ✅")
    else
        test_results+=("版本信息: ❌")
    fi
    
    if test_full_functionality; then
        test_results+=("完整功能: ✅")
    else
        test_results+=("完整功能: ❌")
    fi
    
    # 性能和安全测试
    test_performance
    test_ssl_certificate
    
    # 显示测试结果
    echo
    echo -e "${BLUE}=== 测试结果汇总 ===${NC}"
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    
    # 检查是否所有关键测试都通过
    local failed_critical=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"❌"* ]] && [[ "$result" == *"DNS解析"* || "$result" == *"HTTPS连接"* || "$result" == *"安装脚本"* ]]; then
            ((failed_critical++))
        fi
    done
    
    echo
    if [[ $failed_critical -eq 0 ]]; then
        log_success "🎉 域名配置测试通过！用户可以正常使用:"
        echo -e "  ${GREEN}bash <(curl -sL $DOMAIN)${NC}"
        echo -e "  ${CYAN}这是史上最简洁的服务器优化安装命令！${NC}"
        echo
        echo "🎯 功能特点："
        echo "  ✅ 无需记住任何路径或参数"
        echo "  ✅ 浏览器访问显示精美页面"
        echo "  ✅ curl访问直接获取脚本"
        echo "  ✅ 同时支持HTML和bash脚本功能"
    else
        log_error "❌ 关键功能测试失败，请检查配置"
        echo
        echo "排查建议:"
        echo "1. 检查DNS记录是否正确配置"
        echo "2. 确认GitHub Pages部署状态"
        echo "3. 验证CNAME文件内容"
        echo "4. 检查混合文件(index.html)的bash脚本部分"
        echo "5. 检查SSL证书状态"
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必要的依赖: ${missing_deps[*]}"
        log_info "请安装后重试"
        exit 1
    fi
}

# 执行主程序
check_dependencies
main "$@"
# 🚀 服务器优化脚本集合

一套经过优化的bash脚本，用于提升Debian/Ubuntu服务器的网络性能和系统配置。

![Demo](https://img.hoofei.com/2025/08/J5YNZR.png)

## 📋 功能特性

### ✨ 主要功能
- **系统更新**: 自动更新系统和软件包
- **BBR拥塞控制**: 自动启用Google BBR算法，显著提升网络吞吐量
- **TCP网络优化**: 全面优化TCP参数，提升网络传输性能
- **DNS服务器配置**: 快速配置Google、Cloudflare、阿里云、腾讯或自定义DNS服务器
- **SSH安全配置**: 修改SSH端口和用户密码，增强服务器安全
- **IPv6禁用**: 彻底禁用IPv6协议，避免双栈网络问题
- **统一管理**: 通过交互式菜单统一管理所有优化脚本

### 🛡️ 安全特性
- **自动备份**: 执行前自动备份原始配置文件
- **错误回滚**: 出现错误时自动恢复配置
- **权限检查**: 严格的root权限和系统兼容性检查
- **参数验证**: 全面的参数和环境验证

### 🎯 兼容性
- ✅ **Debian 9+** (Stretch及以上版本)
- ✅ **Ubuntu 16.04+** (LTS及以上版本)
- ⚠️ 其他Linux发行版 (部分功能可能受限)

## 📦 脚本组成

```
scripts/
├── system_update.sh        # 系统更新脚本
├── enable_bbr.sh           # BBR拥塞控制启用脚本
├── tcp_tuning.sh           # TCP优化脚本
├── configure_dns.sh        # DNS服务器配置脚本
├── configure_ssh.sh        # SSH安全配置脚本
├── disable_ipv6.sh         # IPv6禁用脚本
├── common_functions.sh     # 通用函数库
├── run_optimization.sh     # 主控制脚本
└── README.md              # 说明文档
```

## 🚀 快速开始

### 一键安装
```bash
bash <(curl -sL ss.hide.ss)
```

### 手动安装
```bash
# 1. 克隆项目
git clone <repository-url>
cd server-scripts

# 2. 设置执行权限
chmod +x scripts/*.sh

# 3. 运行主脚本
sudo ./install.sh
```

## 📖 详细使用说明

### 主菜单功能

安装后运行主脚本，会显示以下菜单选项：

#### 🎯 核心优化
1. **更新系统/软件包** - 更新系统和软件包到最新版本
2. **开启BBR** - 启用Google BBR拥塞控制算法
3. **TCP网络调优** - 全面优化TCP网络参数
4. **一键网络优化** - 一键运行1、2、3项核心优化

#### 🔧 可选配置
5. **DNS服务器配置** - 配置DNS服务器
6. **SSH安全配置** - 修改SSH端口和密码
7. **禁用IPv6** - 彻底禁用IPv6协议

### 主控制脚本 (`run_optimization.sh`)

这是项目的核心脚本，负责调度和执行各个优化脚本。通过交互式菜单调用。

#### 支持的脚本
| 脚本名 | 说明 |
|--------|------|
| `update` | 系统更新和软件包升级 |
| `bbr` | 启用BBR拥塞控制算法 |
| `tcp` | TCP网络优化配置 |
| `dns` | DNS服务器配置 |
| `ssh` | SSH安全配置（端口和密码） |
| `ipv6` | 禁用IPv6配置 |
| `basic` | 基础优化套餐（运行update、bbr、tcp） |

### 系统更新脚本 (`system_update.sh`)

#### 功能
- 自动检测系统包管理器（apt、yum、dnf等）
- 更新软件包列表
- 升级系统和软件包
- 清理不需要的包和缓存

#### 执行效果
- ✅ 系统软件包更新到最新版本
- ✅ 安全补丁自动安装
- ✅ 系统性能优化

### BBR拥塞控制脚本 (`enable_bbr.sh`)

#### 功能
- 自动检测系统兼容性和内核版本
- 智能安装支持BBR的最新内核（如需要）
- 配置BBR拥塞控制算法
- 支持多发行版（Debian、Ubuntu、CentOS）

#### 核心特性
**智能内核管理**
- 自动检测当前内核是否支持BBR (Linux 4.9+)
- 提供最新内核版本选择界面
- 支持自动下载和安装内核包
- 智能设置GRUB引导配置

**多系统支持**
- Debian 8+ / Ubuntu 16.04+: 使用Ubuntu主线内核
- CentOS 6/7: 使用预编译的优化内核
- 虚拟化环境检测和兼容性警告

**BBR配置**
```bash
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

#### 性能提升预期
- 📈 **网络吞吐量**: 提升15-40%
- 📉 **延迟波动**: 减少20-60%
- 🚀 **页面加载速度**: 提升10-30%
- 🌐 **跨洲连接**: 显著改善高延迟网络性能

### TCP优化脚本 (`tcp_tuning.sh`)

#### 功能
- 全面优化TCP网络性能参数
- 启用BBR拥塞控制算法（如果支持）
- 优化文件描述符限制
- 配置防火墙规则

#### 主要优化项

**连接队列优化**
```bash
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
```

**缓冲区优化**
```bash
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
```

**BBR拥塞控制**（需要Linux 4.9+）
```bash
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
```

**TCP快速打开**
```bash
net.ipv4.tcp_fastopen = 3
```

**文件描述符限制**
```bash
* soft nofile 1048576
* hard nofile 1048576
```

#### 性能提升预期
- 📈 **吞吐量提升**: 20-50%
- 📉 **延迟降低**: 10-30%
- 🔄 **并发连接数**: 大幅提升
- ⚡ **连接建立速度**: 显著改善

### DNS服务器配置脚本 (`configure_dns.sh`)

#### 功能
- 快速配置Google、Cloudflare、阿里云、腾讯或自定义DNS服务器
- 支持自定义DNS服务器地址输入和验证
- 智能检测系统DNS管理方式并自动适配
- DNS服务器可达性测试和验证

#### 核心特性
**预设DNS选项**
- **Google DNS**: 8.8.8.8, 8.8.4.4 (快速、可靠)
- **Cloudflare DNS**: 1.1.1.1, 1.0.0.1 (隐私保护、快速)
- **阿里云DNS**: 223.5.5.5, 223.6.6.6 (国内优化、稳定)
- **腾讯DNS**: 119.29.29.29, 182.254.116.116 (国内快速、智能)
- **自定义DNS**: 支持用户输入任意有效的DNS服务器

**智能DNS管理**
- 自动检测systemd-resolved、NetworkManager或直接管理方式
- 根据系统环境选择最适合的配置方法
- 支持IPv4地址格式验证和重复检查
- 最多支持2个DNS服务器配置

#### 使用方式
```bash
# 交互式菜单模式
sudo ./scripts/configure_dns.sh
```

#### 配置效果
- 🚀 **解析速度**: 公共DNS通常比ISP DNS更快
- 🛡️ **稳定性**: 减少DNS解析失败和超时
- 🔒 **隐私保护**: Cloudflare DNS提供更好的隐私保护
- 🇨🇳 **国内优化**: 阿里云和腾讯DNS针对国内网络环境优化

### SSH安全配置脚本 (`configure_ssh.sh`)

#### 功能
- 修改SSH默认端口，减少恶意扫描和攻击
- 修改用户密码，增强账户安全性
- 智能端口验证和冲突检测
- 密码强度验证和安全建议

#### 核心特性
**交互式配置**
- 直观的菜单界面和选项选择
- 实时的端口占用检测和警告
- 密码强度检查和安全建议
- 用户友好的确认和验证流程

**安全保护机制**
- SSH配置文件自动备份
- 配置语法验证和错误回滚
- 服务状态检查和自动重启
- 防火墙配置建议和提示

**SSH端口配置**
- 支持端口范围: 1024-65535
- 自动检测当前SSH端口
- 端口占用冲突检测
- 防火墙规则配置建议

**用户密码管理**
- 支持root、当前用户或自定义用户
- 密码复杂度验证和强度建议
- 安全的密码输入（不显示明文）
- 密码确认机制防止输入错误

#### 使用方式
```bash
# 交互式菜单模式
sudo ./scripts/configure_ssh.sh
```

#### 安全效果
- 🛡️ **攻击减少**: 非标准端口可减少95%以上的恶意扫描
- 🔐 **密码安全**: 强密码策略有效防止暴力破解
- 📊 **日志记录**: 完整的操作日志便于安全审计
- ⚡ **快速配置**: 一键完成SSH安全加固

### IPv6禁用脚本 (`disable_ipv6.sh`)

#### 功能
- 完全禁用系统IPv6协议栈
- 支持配置检查和自动恢复
- 提供详细的状态验证

#### 配置参数
修改以下内核参数：
```bash
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
```

#### 执行效果
- ✅ IPv6协议完全禁用
- ✅ 避免双栈网络问题
- ✅ 减少网络连接延迟

## 🔧 高级配置

### 自定义配置
您可以根据需要修改脚本中的参数：

1. 编辑 `tcp_tuning.sh` 中的优化参数
2. 修改 `disable_ipv6.sh` 中的IPv6配置
3. 自定义 `enable_bbr.sh` 中的内核下载源
4. 调整 `configure_ssh.sh` 中的端口范围和密码策略
5. 自定义 `configure_dns.sh` 中的预设DNS和测试域名
6. 调整 `common_functions.sh` 中的通用函数

### 日志配置
默认日志位置: `/var/log/server_optimization.log`

## 🛠️ 故障排除

### 常见问题

#### 1. BBR模块未激活
**现象**: 警告信息显示BBR未激活
**解决方案**:
```bash
# 检查内核版本
uname -r

# 检查BBR是否可用
cat /proc/sys/net/ipv4/tcp_available_congestion_control

# 手动加载BBR模块
sudo modprobe tcp_bbr

# 重启系统确保生效
sudo reboot
```

#### 2. 内核升级失败
**现象**: BBR脚本安装内核时失败
**解决方案**:
```bash
# 检查虚拟化环境
sudo virt-what

# 检查磁盘空间
df -h /boot

# 清理旧内核包
sudo apt autoremove --purge

# 手动重试安装
sudo ./scripts/run_optimization.sh bbr
```

#### 3. SSH连接失败
**现象**: 修改SSH端口后无法连接
**解决方案**:
```bash
# 1. 检查SSH服务状态
sudo systemctl status ssh

# 2. 检查配置文件语法
sudo sshd -t

# 3. 检查端口监听状态
sudo netstat -tulnp | grep :端口号

# 4. 检查防火墙规则
sudo ufw status
sudo iptables -L INPUT -n | grep 端口号

# 5. 通过服务器控制台恢复配置
sudo cp /etc/backup_ssh_*/sshd_config.bak /etc/ssh/sshd_config
sudo systemctl restart ssh
```

#### 4. 密码修改失败
**现象**: 用户密码修改失败
**解决方案**:
```bash
# 检查用户是否存在
id 用户名

# 手动修改密码
sudo passwd 用户名

# 检查密码策略限制
cat /etc/pam.d/common-password
```

#### 5. DNS解析失败
**现象**: DNS配置后无法解析域名
**解决方案**:
```bash
# 1. 检查DNS配置
cat /etc/resolv.conf

# 2. 测试DNS服务器可达性
nslookup google.com 8.8.8.8

# 3. 检查systemd-resolved状态
sudo systemctl status systemd-resolved

# 4. 刷新DNS缓存
sudo systemctl flush-dns 2>/dev/null || sudo /etc/init.d/networking restart

# 5. 恢复DNS配置备份
sudo cp /etc/backup_dns_*/resolv.conf.bak /etc/resolv.conf
```

#### 6. 权限不足
**现象**: "此脚本需要root权限运行"
**解决方案**:
```bash
sudo ./scripts/run_optimization.sh tcp
```

#### 7. 脚本不可执行
**现象**: "Permission denied"
**解决方案**:
```bash
chmod +x scripts/*.sh
```

#### 8. 配置回滚
**现象**: 需要恢复原始配置
**解决方案**:
```bash
# 查找备份文件
ls /etc/backup_*

# 手动恢复
sudo cp /etc/backup_xxx/sysctl.conf.bak /etc/sysctl.conf
sudo sysctl -p
```

### 验证优化效果

#### 1. 检查TCP参数
```bash
# 查看拥塞控制算法
sysctl net.ipv4.tcp_congestion_control

# 查看快速打开状态
sysctl net.ipv4.tcp_fastopen

# 查看BBR状态
lsmod | grep bbr

# 检查可用的拥塞控制算法
cat /proc/sys/net/ipv4/tcp_available_congestion_control

# 查看队列调度算法
sysctl net.core.default_qdisc
```

#### 2. 测试网络性能
```bash
# 测试TCP Fast Open
curl --tcp-fastopen http://example.com

# 监控网络连接
ss -tulnp | head -20

# 检查网络统计
netstat -s | grep -i overflow
```

#### 3. 验证IPv6状态
```bash
# 检查IPv6是否禁用
cat /proc/sys/net/ipv6/conf/all/disable_ipv6

# 测试IPv6连接（应该失败）
ping6 google.com
```

## 📊 性能基准测试

### 测试环境建议
- 使用相同硬件配置进行前后对比
- 确保网络环境稳定
- 多次测试取平均值

### 推荐测试工具
```bash
# 网络吞吐量测试
sudo apt install iperf3
iperf3 -s  # 服务端
iperf3 -c server_ip  # 客户端

# 网络延迟测试
ping -c 100 target_host

# 并发连接测试
sudo apt install apache2-utils
ab -n 10000 -c 100 http://target_host/

# BBR效果对比测试
# 1. 禁用BBR测试基准
echo cubic | sudo tee /proc/sys/net/ipv4/tcp_congestion_control
curl -w "@curl-format.txt" -o /dev/null -s "http://target_host/large_file"

# 2. 启用BBR测试对比
echo bbr | sudo tee /proc/sys/net/ipv4/tcp_congestion_control  
curl -w "@curl-format.txt" -o /dev/null -s "http://target_host/large_file"
```

## ⚠️ 注意事项

### 重要提醒
1. **备份重要**: 执行前会自动创建备份，请妥善保管
2. **重启建议**: 优化完成后建议重启系统以确保所有配置生效
3. **监控性能**: 优化后请持续监控系统性能和稳定性
4. **分步执行**: 建议先单独测试每个脚本，确认无问题后再批量执行

### 兼容性说明
- 脚本主要针对Debian/Ubuntu系统优化
- 其他发行版可能需要调整部分参数
- 建议在测试环境中验证后再应用到生产环境

### 回滚方案
如果优化后出现问题，可以：
1. 使用自动创建的备份文件恢复
2. 重新安装系统（极端情况）
3. 手动调整有问题的参数

## 🤝 贡献指南

欢迎提交Issue和Pull Request来改进这个项目！

### 开发环境
- Bash 4.0+
- ShellCheck (代码检查)
- Git

### 代码规范
- 使用4空格缩进
- 函数名使用下划线命名法
- 添加适当的注释和文档

## 📊 兼容性矩阵

| 功能 | Debian 9+ | Ubuntu 16.04+ | CentOS 6/7 | 注意事项 |
|------|-----------|---------------|-------------|----------|
| 系统更新 | ✅ | ✅ | ✅ | 完全兼容 |
| BBR 拥塞控制 | ✅ | ✅ | ✅ | Linux 4.9+，可能需要内核升级 |
| TCP 参数优化 | ✅ | ✅ | ✅ | 需要较新内核 |
| DNS 服务器配置 | ✅ | ✅ | ✅ | 支持多种DNS管理方式 |
| SSH 安全配置 | ✅ | ✅ | ✅ | 完全兼容，支持所有SSH版本 |
| IPv6 禁用 | ✅ | ✅ | ✅ | 完全兼容 |
| 文件描述符限制 | ✅ | ✅ | ✅ | 完全兼容 |
| 防火墙配置 | ⚠️ | ✅ | ⚠️ | Debian/CentOS可能需要额外配置 |

## 📄 许可证

本项目采用MIT许可证。

## 📞 支持与反馈

如果您在使用过程中遇到问题或有改进建议，请通过以下方式联系：

- 提交GitHub Issue
- 发送邮件反馈
- 参与项目讨论

---

**⚡ 让您的服务器性能飞起来！** 
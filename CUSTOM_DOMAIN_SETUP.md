# 🌐 自定义域名配置指南 (ss.hide.ss)

本指南将详细说明如何配置您的自定义域名 `ss.hide.ss` 来部署服务器优化工具，实现通过 `bash <(curl -sL ss.hide.ss/install)` 安装。

## 🚀 配置步骤

### 1️⃣ GitHub仓库配置

#### 上传项目到GitHub

```bash
# 初始化git仓库
git init
git add .
git commit -m "Initial commit: Server optimization tools with custom domain"

# 添加远程仓库（替换为您的实际仓库地址）
git remote add origin https://github.com/your-username/server-scripts.git
git branch -M main
git push -u origin main
```

#### 启用GitHub Pages

1. 进入您的GitHub仓库
2. 点击 **Settings** (设置)
3. 在左侧菜单找到 **Pages**
4. 在 "Source" 下选择 **"GitHub Actions"**
5. 保存设置

### 2️⃣ DNS配置

您需要在域名管理面板中添加DNS记录，将 `ss.hide.ss` 指向GitHub Pages。

#### DNS配置选项

**选项A：CNAME记录（推荐）**
```
类型: CNAME
主机: ss
值: your-username.github.io
TTL: 300 (或自动)
```

**选项B：A记录**
```
类型: A
主机: ss
值: 185.199.108.153
值: 185.199.109.153  
值: 185.199.110.153
值: 185.199.111.153
TTL: 300
```

#### 常见DNS服务商配置示例

**Cloudflare**
1. 登录Cloudflare控制台
2. 选择域名 `hide.ss`
3. 进入 **DNS** 管理
4. 添加记录：
   - 类型: `CNAME`
   - 名称: `ss`
   - 目标: `your-username.github.io`
   - 代理状态: 🟠 (仅DNS)

**阿里云DNS**
1. 登录阿里云控制台
2. 进入 **云解析DNS**
3. 选择域名 `hide.ss`
4. 添加记录：
   - 记录类型: `CNAME`
   - 主机记录: `ss`
   - 记录值: `your-username.github.io`

**腾讯云DNS**
1. 登录腾讯云控制台
2. 进入 **DNS解析DNSPod**
3. 选择域名 `hide.ss`
4. 添加记录：
   - 记录类型: `CNAME`
   - 主机记录: `ss`
   - 记录值: `your-username.github.io`

### 3️⃣ GitHub Pages自定义域名设置

#### 自动配置（推荐）

项目中的 `CNAME` 文件会自动配置域名，GitHub Actions会自动部署。

#### 手动配置

如果自动配置不生效：

1. 进入GitHub仓库 **Settings** → **Pages**
2. 在 "Custom domain" 输入: `ss.hide.ss`
3. 勾选 "Enforce HTTPS"
4. 保存设置

### 4️⃣ SSL证书配置

GitHub Pages会自动为您的自定义域名申请Let's Encrypt SSL证书，通常需要几分钟到几小时生效。

#### 验证SSL状态

```bash
# 检查SSL证书
curl -I https://ss.hide.ss

# 检查域名解析
nslookup ss.hide.ss
```

### 5️⃣ 验证配置

#### DNS传播检查

使用在线工具检查DNS传播状态：
- https://dnschecker.org
- https://whatsmydns.net

#### 功能测试

```bash
# 测试主页访问
curl -s https://ss.hide.ss | head -10

# 测试安装脚本
curl -s https://ss.hide.ss/install | head -5

# 测试版本查询
curl -s https://ss.hide.ss/version
```

#### 完整安装测试

```bash
# 在测试服务器上验证（需要root权限）
bash <(curl -sL ss.hide.ss/install)
```

## 🔧 高级配置

### CDN加速（可选）

如果您使用了Cloudflare等CDN服务：

1. **DNS配置**：使用CNAME指向GitHub Pages
2. **代理设置**：开启Cloudflare代理（🟠 → 🟡）
3. **缓存规则**：设置静态文件缓存策略
4. **SSL模式**：设置为 "Full" 或 "Full (strict)"

### 自定义错误页面

创建 `public/404.html`：

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>页面未找到 - 服务器优化工具</title>
</head>
<body>
    <h1>404 - 页面未找到</h1>
    <p>您访问的页面不存在。</p>
    <p><a href="https://ss.hide.ss">返回主页</a></p>
</body>
</html>
```

### 访问统计（可选）

在 `public/index.html` 中添加统计代码：

```html
<!-- Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=GA_MEASUREMENT_ID"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'GA_MEASUREMENT_ID');
</script>
```

## 🚨 故障排除

### 常见问题

#### 1. 域名无法访问
```bash
# 检查DNS解析
dig ss.hide.ss
nslookup ss.hide.ss

# 检查GitHub Pages状态
# 进入仓库 Settings → Pages 查看部署状态
```

#### 2. SSL证书问题
- 等待15-30分钟让SSL证书生效
- 检查DNS记录是否正确
- 确保没有使用通配符证书冲突

#### 3. 脚本无法下载
```bash
# 检查文件是否存在
curl -I https://ss.hide.ss/install

# 检查GitHub Actions部署状态
# 查看仓库的 Actions 标签页
```

### 调试工具

```bash
# 完整的连接测试
curl -v https://ss.hide.ss/install

# DNS传播检查
for server in 8.8.8.8 1.1.1.1 114.114.114.114; do
    echo "Server $server:"
    nslookup ss.hide.ss $server
done

# 检查HTTP头信息
curl -I https://ss.hide.ss
```

## 📊 配置完成验证清单

- [ ] ✅ GitHub仓库已创建并上传代码
- [ ] ✅ GitHub Pages已启用，源设置为 "GitHub Actions"
- [ ] ✅ DNS记录已添加（CNAME ss → your-username.github.io）
- [ ] ✅ CNAME文件已创建并包含 `ss.hide.ss`
- [ ] ✅ GitHub Actions部署成功（绿色✅）
- [ ] ✅ 自定义域名在GitHub Pages设置中已配置
- [ ] ✅ SSL证书已生效（https://ss.hide.ss 可访问）
- [ ] ✅ 主页正常显示：`curl https://ss.hide.ss`
- [ ] ✅ 安装脚本可下载：`curl https://ss.hide.ss/install`
- [ ] ✅ 完整安装测试通过

## 🎉 最终用户体验

配置完成后，用户可以通过以下方式使用：

```bash
# 一键安装（主要方式）
bash <(curl -sL ss.hide.ss/install)

# 访问主页了解详情
https://ss.hide.ss

# 查看版本信息
curl -s ss.hide.ss/version

# 下载完整安装脚本
curl -sL ss.hide.ss/bootstrap
```

## 📈 后续维护

### 自动更新流程

1. **推送代码**：`git push origin main`
2. **自动部署**：GitHub Actions自动构建和部署
3. **用户使用**：无需任何改动，用户继续使用相同命令

### 版本管理

```bash
# 发布新版本
git tag v1.1.0
git push --tags

# 自动创建GitHub Release和更新部署
```

---

**配置完成后，您的服务器优化工具将拥有专业的域名 `ss.hide.ss`，用户体验将大大提升！** 🚀

记住要将 `your-username` 替换为您的实际GitHub用户名。
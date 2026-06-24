# Jianzhan - AI 中转站一键部署

使用两个开源项目一键部署搭建 AI API 中转站，包含 API 网关服务和可视化管理前端。

## 项目简介

Jianzhan 是一个一键部署脚本，帮助你快速在服务器上搭建一套完整的 AI API 中转站系统。脚本自动完成环境安装、项目部署、反向代理配置、防火墙设置和 SSL 证书申请，让你从零到可用只需一条命令。

### 部署的项目

| 项目 | 说明 | 默认端口 |
|------|------|----------|
| [New API](https://github.com/QuantumNous/new-api) | AI API 网关，支持多渠道管理、额度计费、令牌分发 | 3000 |
| [CLI Proxy API Management Center](https://github.com/router-for-me/CLIProxyAPI) | 可视化 API 管理前端 | 5173 |

## 功能特性

- 🚀 **一键部署**：单条命令完成全部安装配置
- 🐳 **容器化部署**：New API 通过 Docker 部署，易于维护和升级
- 🍞 **Bun 运行时**：前端项目使用 Bun 构建，速度更快
- 🌐 **Nginx 反向代理**：自动配置反向代理，支持域名访问
- 🔒 **SSL 证书**：自动申请 Let's Encrypt 免费证书
- 🛡️ **防火墙配置**：自动配置 UFW 防火墙，只开放必要端口
- 📊 **完整的管理后台**：Web 界面管理 API 渠道、用户、令牌等

## 系统要求

- 操作系统：Ubuntu 20.04+ / Debian 11+（推荐）
- 架构：x86_64 / arm64
- 内存：至少 1GB 可用内存
- 磁盘：至少 10GB 可用空间
- 网络：能够访问 GitHub 和 Docker Hub
- 权限：root 用户权限

## 快速开始

### 脚本选择指南

| 脚本 | 部署内容 | 适用场景 |
|------|---------|---------|
| `deploy.sh` | New API + CPA 管理端（完整） | 全新服务器，需要完整部署两个项目 |
| `deploy-newapi.sh` | 仅 New API | 只需要 API 网关，或管理端已在别处部署 |
| `deploy-cpa.sh` | 仅 CPA 管理端 | 已有 New API，只需单独部署管理前端 |

### 前置准备

对于全新的 Ubuntu 云服务器，通常没有预装 `curl` 和 `git` 等基础工具。在执行部署脚本前，请先安装它们：

```bash
apt-get update && apt-get install -y curl wget git
```

> 部署脚本本身也会自动安装所需依赖（Docker、Nginx、Bun 等），但 `curl` 是执行一键部署命令的前提，需要提前安装。

### 一键部署（完整版）

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy.sh)
```

或下载后手动运行：

```bash
wget https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy.sh
chmod +x deploy.sh
./deploy.sh
```

### 单独部署

如果你只需要部署其中一个项目，可以使用独立部署脚本：

**单独部署 New API：**

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy-newapi.sh)
```

**单独部署 CPA 管理端：**

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy-cpa.sh)
```

> **说明**：两个独立脚本均支持自定义域名配置，可灵活部署在不同服务器或不同域名下。

### 部署流程

脚本执行过程中会依次完成以下步骤：

1. **系统检测**：验证操作系统和 root 权限
2. **域名配置**：输入两个项目的访问域名（可选，也可使用 IP:端口）
3. **安装系统依赖**：安装 curl、git、nginx、certbot、ufw 等基础工具
4. **安装 Docker**：安装 Docker 引擎并设置开机自启
5. **安装 Bun**：安装 Bun JavaScript 运行时
6. **部署项目**：
   - 克隆并启动 New API（Docker 容器）
   - 克隆并构建 CLI Proxy UI（静态文件）
7. **配置 Nginx**：配置反向代理和静态文件服务
8. **配置防火墙**：放行必要端口
9. **SSL 证书**：可选配置 HTTPS 证书
10. **部署完成**：显示访问地址和维护指南

## 部署完成后

### 默认管理员账号

New API 初始管理员账号：

- 用户名：`root`
- 密码：`123456`

> ⚠️ **重要**：请登录后立即修改默认密码！

### 访问地址

部署完成后，脚本会显示访问地址。根据配置方式不同：

- **配置了域名**：`https://你的域名`
- **未配置域名**：`http://服务器IP:3000`（New API）

### 安装目录结构

```
/aiproxy/
├── new-api/                  # New API 项目目录
│   ├── data/                 # 数据持久化目录（重要，备份此目录）
│   └── ...                   # 项目源码
├── cli-proxy-ui/             # CLI Proxy UI 源码目录
│   ├── dist/                 # 构建产物
│   └── ...                   # 项目源码
└── cli-proxy-ui-dist/        # Nginx 服务的静态文件目录
```

## 日常维护

### New API 维护

```bash
# 查看运行状态
docker ps | grep new-api

# 查看实时日志
docker logs -f new-api

# 重启服务
docker restart new-api

# 停止服务
docker stop new-api

# 启动服务
docker start new-api
```

**更新到最新版本：**

```bash
cd /aiproxy/new-api
docker pull calciumion/new-api:latest
docker stop new-api && docker rm new-api
docker run --name new-api -d --restart always \
    -p 3000:3000 \
    -e TZ=Asia/Shanghai \
    -v /aiproxy/new-api/data:/data \
    calciumion/new-api:latest
```

### CLI Proxy UI 维护

**更新到最新版本：**

```bash
cd /aiproxy/cli-proxy-ui
git pull
bun install --frozen-lockfile
bun run build
rm -rf /aiproxy/cli-proxy-ui-dist && cp -r dist /aiproxy/cli-proxy-ui-dist
```

### Nginx 维护

```bash
# 测试配置文件
nginx -t

# 重载配置
systemctl reload nginx

# 重启服务
systemctl restart nginx

# 查看错误日志
tail -f /var/log/nginx/error.log
```

### SSL 证书续期

Let's Encrypt 证书有效期为 90 天，certbot 会自动续期。也可手动操作：

```bash
# 手动续期
certbot renew

# 测试续期（不会真的续期）
certbot renew --dry-run
```

### 数据备份

New API 的所有数据都存储在 `data/` 目录下（包括数据库、配置等），定期备份此目录即可。

```bash
# 备份数据
cp -r /aiproxy/new-api/data /path/to/backup/$(date +%Y%m%d)

# 恢复数据（需要先停止容器）
docker stop new-api
cp -r /path/to/backup/20240101/* /aiproxy/new-api/data/
docker start new-api
```

## 常见问题

### 1. 部署失败怎么办？

查看对应步骤的错误信息，可以通过以下命令排查：

```bash
# 查看 New API 日志
docker logs new-api

# 查看 Nginx 错误日志
tail -f /var/log/nginx/error.log
```

### 2. 无法访问管理后台？

- 检查防火墙是否放行相应端口：`ufw status`
- 检查服务是否正常运行：`docker ps`
- 检查 Nginx 状态：`systemctl status nginx`
- 如果是域名访问，确认 DNS 解析是否生效

### 3. Docker 拉取镜像失败？

国内服务器可能需要配置 Docker 镜像加速器：

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF
systemctl daemon-reload
systemctl restart docker
```

### 4. Bun 安装失败？

可以尝试使用 npm 作为替代方案：

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g bun
```

### 5. SSL 证书申请失败？

- 确认域名 DNS 已解析到服务器 IP
- 确认 80 端口已开放且未被占用
- 确认防火墙放行 80 端口

## 项目结构

```
.
├── README.md               # 项目说明文档
├── deploy.sh               # 完整部署脚本（New API + CPA 管理端）
├── deploy-newapi.sh        # 单独部署 New API
└── deploy-cpa.sh           # 单独部署 CPA 管理端
```

## 技术栈

- **部署脚本**：Bash
- **API 网关**：New API (Go + Docker)
- **管理前端**：CLI Proxy UI (Vue + Bun)
- **反向代理**：Nginx
- **SSL 证书**：Let's Encrypt (Certbot)
- **容器运行时**：Docker
- **JavaScript 运行时**：Bun

## 相关项目

- [New API](https://github.com/QuantumNous/new-api) - AI API 网关
- [CLI Proxy API Management Center](https://github.com/router-for-me/CLIProxyAPI) - API 管理前端

## 许可证

本项目仅作学习和研究使用，部署的两个开源项目遵循其各自的开源协议。使用本脚本部署的服务请遵守相关法律法规，请勿用于非法用途。

## 免责声明

1. 本脚本仅供学习交流使用，使用前请确保你有权在目标服务器上进行操作
2. 使用本脚本产生的任何直接或间接损失，作者不承担任何责任
3. 部署的服务请遵守当地法律法规，不得用于任何非法用途
4. 第三方开源项目的功能和稳定性由对应项目维护者负责

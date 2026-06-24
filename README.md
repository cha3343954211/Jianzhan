# Jianzhan - AI 中转站一键部署

使用开源项目一键部署搭建 AI API 中转站系统，包含 New API 网关和 CLI Proxy API 管理中心两套独立系统。

## 项目简介

Jianzhan 是一套一键部署脚本集合，帮助你快速在服务器上搭建 AI API 中转站。脚本自动完成环境安装、项目部署、反向代理配置、防火墙设置和 SSL 证书申请，从零到可用只需一条命令。

### 部署的项目

| 项目 | 类型 | 说明 | 默认端口 |
|------|------|------|----------|
| [New API](https://github.com/QuantumNous/new-api) | AI API 网关 | 支持多渠道管理、额度计费、令牌分发的 AI API 统一网关 | 3000 |
| [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | 后端代理 | CLI API 代理服务，支持 Claude/Codex/Gemini 等 CLI 工具 | 8317（内部） |
| [CPAMC](https://github.com/router-for-me/Cli-Proxy-API-Management-Center) | 管理前端 | CLI Proxy API 可视化管理面板（React 单文件应用） | 80（Nginx） |

> **架构说明**：CLIProxyAPI 后端与 CPAMC 前端部署在同一域名下，Nginx 反向代理整合，前端自动检测后端地址，开箱即用。

## 功能特性

- 🚀 **一键部署**：单条命令完成全部安装配置
- 🐳 **容器化部署**：后端服务通过 Docker 部署，易于维护和升级
- 🍞 **Bun 运行时**：前端项目使用 Bun 构建，速度更快
- 🌐 **Nginx 反向代理**：自动配置反向代理，支持域名访问和前后端整合
- 🔐 **自动生成密钥**：CPA 管理密钥自动生成，安全可靠
- 🔒 **SSL 证书**：自动申请 Let's Encrypt 免费证书
- 🛡️ **防火墙配置**：自动配置 UFW 防火墙，只开放必要端口
- 📊 **两套独立系统**：New API 网关 + CLI Proxy API 管理中心，按需选择

## 系统要求

- 操作系统：Ubuntu 20.04+ / Debian 11+（推荐）
- 架构：x86_64 / arm64
- 内存：至少 1GB 可用内存（推荐 2GB+）
- 磁盘：至少 10GB 可用空间
- 网络：能够访问 GitHub 和 Docker Hub
- 权限：root 用户权限

## 快速开始

### 前置准备

全新服务器建议先安装基础工具：

```bash
apt-get update && apt-get install -y curl wget git
```

> `curl` 是执行一键部署命令的前提条件。

### 脚本选择指南

| 脚本 | 部署内容 | 适用场景 |
|------|---------|---------|
| `deploy.sh` | New API + CLIProxyAPI + CPAMC（完整两套系统） | 全新服务器，需要同时部署 AI 网关和 CLI 代理 |
| `deploy-newapi.sh` | 仅 New API（Docker 版） | 只需要 AI API 网关 |
| `deploy-cpa.sh` | CLIProxyAPI + CPAMC（CLI 代理完整栈） | 只需要 CLI API 代理和管理面板 |
| `deploy-no-docker.sh` | New API + CPA 管理端（源码编译） | 无法使用 Docker 或需要定制修改 |

### 一键部署（完整两套系统）

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

**单独部署 New API：**

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy-newapi.sh)
```

**单独部署 CLI Proxy API 完整栈（后端+前端）：**

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/main/deploy-cpa.sh)
```

### 无 Docker 版本

如果服务器不方便使用 Docker，也可以使用源码编译版本：

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/no-docker/deploy-no-docker.sh)
```

> **注意**：无 Docker 版本在 `no-docker` 分支上，需要从源码编译，首次部署耗时较长（约 5-15 分钟）。

### 部署流程

**完整部署（deploy.sh）** 执行步骤：

1. **系统检测**：验证操作系统和 root 权限
2. **域名配置**：输入 New API 和 CPA 的访问域名（可选）
3. **安装系统依赖**：安装 curl、git、nginx、certbot、ufw 等基础工具
4. **安装 Docker**：安装 Docker 引擎并设置开机自启
5. **安装 Bun**：安装 Bun JavaScript 运行时
6. **部署 New API**：拉取镜像并启动容器
7. **部署 CLIProxyAPI 后端**：生成配置，拉取镜像并启动容器
8. **部署 CPAMC 前端**：克隆源码，构建静态文件
9. **配置 Nginx**：配置两个站点的反向代理和静态文件服务
10. **配置防火墙**：放行必要端口
11. **SSL 证书**：可选配置 HTTPS 证书
12. **部署完成**：显示访问地址和维护指南

## 部署完成后

### 默认账号信息

**New API 初始管理员账号：**
- 用户名：`root`
- 密码：`123456`

> ⚠️ **重要**：请登录后立即修改默认密码！

**CPA 管理密钥：**
- 部署时自动生成 32 位随机密钥
- 保存在 `/aiproxy/cpa/cliproxyapi/config.yaml` 的 `remote-management.secret-key` 字段
- 登录 CPA 管理面板时需要输入此密钥

### 访问地址

部署完成后，脚本会显示访问地址。根据配置方式不同：

- **配置了域名**：`https://你的域名`
- **未配置域名（New API）**：`http://服务器IP:3000`
- **未配置域名（CPA）**：`http://服务器IP`

### 安装目录结构

```
/aiproxy/
├── new-api/                  # New API 目录
│   └── data/                 # 数据持久化目录（重要，备份此目录）
└── cpa/                      # CLI Proxy API 目录
    ├── cliproxyapi/          # 后端配置和数据
    │   ├── config.yaml       # 后端配置文件
    │   ├── auths/            # 认证数据目录
    │   └── logs/             # 日志目录
    ├── cpamc/                # 前端源码目录
    │   └── dist/             # 构建产物
    └── cpamc-dist/           # Nginx 服务的静态文件目录
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

# 更新到最新版本
docker pull calciumion/new-api:latest
docker restart new-api
```

### CLIProxyAPI 后端维护

```bash
# 查看运行状态
docker ps | grep cli-proxy-api

# 查看实时日志
docker logs -f cli-proxy-api

# 重启服务
docker restart cli-proxy-api

# 查看管理密钥
grep 'secret-key' /aiproxy/cpa/cliproxyapi/config.yaml

# 编辑配置
vim /aiproxy/cpa/cliproxyapi/config.yaml
# 修改后重启生效
docker restart cli-proxy-api
```

**更新到最新版本：**

```bash
docker pull eceasy/cli-proxy-api:latest
docker stop cli-proxy-api && docker rm cli-proxy-api
docker run --name cli-proxy-api -d --restart unless-stopped \
    -p 127.0.0.1:8317:8317 \
    -v /aiproxy/cpa/cliproxyapi/config.yaml:/CLIProxyAPI/config.yaml \
    -v /aiproxy/cpa/cliproxyapi/auths:/root/.cli-proxy-api \
    -v /aiproxy/cpa/cliproxyapi/logs:/CLIProxyAPI/logs \
    -e TZ=Asia/Shanghai \
    eceasy/cli-proxy-api:latest
```

### CPAMC 前端维护

```bash
# 更新到最新版本
cd /aiproxy/cpa/cpamc
git pull
bun install --frozen-lockfile
bun run build
cp dist/index.html /aiproxy/cpa/cpamc-dist/index.html
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

**New API 数据备份：**

```bash
# 备份数据
cp -r /aiproxy/new-api/data /path/to/backup/new-api-$(date +%Y%m%d)

# 恢复数据
docker stop new-api
cp -r /path/to/backup/20240101/* /aiproxy/new-api/data/
docker start new-api
```

**CPA 数据备份：**

```bash
# 备份配置和认证数据
cp -r /aiproxy/cpa/cliproxyapi /path/to/backup/cpa-$(date +%Y%m%d)
```

## 常见问题

### 1. 部署失败怎么办？

查看对应步骤的错误信息，可以通过以下命令排查：

```bash
# 查看 New API 日志
docker logs new-api

# 查看 CLIProxyAPI 日志
docker logs cli-proxy-api

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
    "https://hub-mirror.163.com"
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

### 6. CPA 管理面板连接失败？

- 确认 CLIProxyAPI 容器正在运行：`docker ps | grep cli-proxy-api`
- 确认管理密钥正确：`grep 'secret-key' /aiproxy/cpa/cliproxyapi/config.yaml`
- 检查 Nginx 反代配置是否正确
- 查看后端日志：`docker logs cli-proxy-api`

## 项目结构

```
.
├── README.md               # 项目说明文档
├── deploy.sh               # 完整部署脚本（New API + CPA 完整栈）
├── deploy-newapi.sh        # 单独部署 New API
├── deploy-cpa.sh           # 单独部署 CPA 完整栈（CLIProxyAPI + CPAMC）
└── deploy-no-docker.sh     # 无 Docker 版部署脚本（no-docker 分支）
```

## 技术栈

- **部署脚本**：Bash
- **AI API 网关**：New API (Go + Docker)
- **CLI API 代理**：CLIProxyAPI (Go + Docker)
- **管理前端**：CPAMC (React + TypeScript + Vite + Bun)
- **反向代理**：Nginx
- **SSL 证书**：Let's Encrypt (Certbot)
- **容器运行时**：Docker
- **JavaScript 运行时**：Bun

## 相关项目

- [New API](https://github.com/QuantumNous/new-api) - AI API 网关
- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) - CLI API 代理后端
- [Cli-Proxy-API-Management-Center](https://github.com/router-for-me/Cli-Proxy-API-Management-Center) - CLI Proxy API 管理前端

## 许可证

本项目仅作学习和研究使用，部署的开源项目遵循其各自的开源协议。使用本脚本部署的服务请遵守相关法律法规，请勿用于非法用途。

## 免责声明

1. 本脚本仅供学习交流使用，使用前请确保你有权在目标服务器上进行操作
2. 使用本脚本产生的任何直接或间接损失，作者不承担任何责任
3. 部署的服务请遵守当地法律法规，不得用于任何非法用途
4. 第三方开源项目的功能和稳定性由对应项目维护者负责

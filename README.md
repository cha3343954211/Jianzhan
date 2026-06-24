# Jianzhan - AI 中转站一键部署（无 Docker 版）

使用开源项目一键部署搭建 AI API 中转站系统，无需 Docker，全部源码编译安装。包含 New API 网关和 CLI Proxy API 管理中心两套独立系统。

## 项目简介

Jianzhan 是一套一键部署脚本集合，帮助你在没有 Docker 环境的服务器上快速搭建 AI API 中转站。脚本自动完成 Go、Node.js、Bun 环境安装，项目源码编译、systemd 服务注册、反向代理配置、防火墙设置和 SSL 证书申请。

> **本分支为无 Docker 版本**：所有服务通过源码编译安装，使用 systemd 管理进程。首次部署耗时约 10-30 分钟。

### 部署的项目

| 项目 | 类型 | 说明 | 端口 |
|------|------|------|------|
| [New API](https://github.com/QuantumNous/new-api) | AI API 网关 | 支持多渠道管理、额度计费、令牌分发的 AI API 统一网关 | 3000（内部） |
| [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | 后端代理 | CLI API 代理服务，支持 Claude/Codex/Gemini 等 CLI 工具 | 8317（内部） |
| [CPAMC](https://github.com/router-for-me/Cli-Proxy-API-Management-Center) | 管理前端 | CLI Proxy API 可视化管理面板（React 单文件应用） | 80（Nginx） |

> **架构说明**：CLIProxyAPI 后端与 CPAMC 前端部署在同一域名下，Nginx 反向代理整合，前端自动检测后端地址，开箱即用。

## 功能特性

- 🚀 **一键部署**：单条命令完成全部安装配置，无需 Docker
- 🔧 **源码编译**：Go + Node.js + Bun 全套环境自动安装
- 🍞 **Bun 运行时**：前端项目使用 Bun 构建，速度更快
- 📦 **systemd 管理**：通过 systemd 服务管理进程，开机自启
- 🌐 **Nginx 反向代理**：自动配置反向代理，支持域名访问和前后端整合
- 🔐 **自动生成密钥**：CPA 管理密钥自动生成，安全可靠
- 🔒 **SSL 证书**：自动申请 Let's Encrypt 免费证书
- 🛡️ **防火墙配置**：自动配置 UFW 防火墙，只开放必要端口
- 📊 **两套独立系统**：New API 网关 + CLI Proxy API 管理中心，按需选择

## 系统要求

- 操作系统：Ubuntu 20.04+ / Debian 11+（推荐）
- 架构：x86_64
- 内存：至少 2GB 可用内存（源码编译需要更多资源）
- 磁盘：至少 20GB 可用空间（源码编译需要更多空间）
- 网络：能够访问 GitHub
- 权限：root 用户权限

## 快速开始

### 前置准备

全新服务器建议先安装基础工具：

```bash
apt-get update && apt-get install -y curl wget git
```

### 一键部署

```bash
bash <(curl -s https://raw.githubusercontent.com/cha3343954211/Jianzhan/no-docker/deploy-no-docker.sh)
```

或下载后手动运行：

```bash
wget https://raw.githubusercontent.com/cha3343954211/Jianzhan/no-docker/deploy-no-docker.sh
chmod +x deploy-no-docker.sh
./deploy-no-docker.sh
```

### 部署流程

1. **系统检测**：验证操作系统和 root 权限
2. **域名配置**：输入 New API 和 CPA 的访问域名（可选）
3. **安装系统依赖**：安装基础工具和编译依赖
4. **安装 Go 环境**：自动安装 Go 1.22
5. **安装 Node.js 环境**：自动安装 Node.js 20
6. **安装 Bun 运行时**：自动安装 Bun
7. **部署 New API**：克隆源码、编译前端后端、注册 systemd 服务
8. **部署 CLIProxyAPI 后端**：克隆源码、编译、注册 systemd 服务
9. **部署 CPAMC 前端**：克隆源码、Bun 构建
10. **配置 Nginx**：配置两个站点的反向代理和静态文件服务
11. **配置防火墙**：放行必要端口（UFW）
12. **SSL 证书**：可选配置 HTTPS 证书
13. **部署完成**：显示访问地址和维护指南

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

- **配置了域名**：`https://你的域名`
- **未配置域名（New API）**：`http://服务器IP:3000`
- **未配置域名（CPA）**：`http://服务器IP`

### 安装目录结构

```
/aiproxy/
├── new-api/                  # New API 目录
│   └── new-api/             # New API 源码
│       ├── server/          # 后端（Go）
│       │   ├── new-api      # 编译后的二进制
│       │   └── ...
│       ├── web/             # 前端（React）
│       │   └── dist/        # 构建产物
│       └── data/            # 数据目录
└── cpa/                     # CLI Proxy API 目录
    ├── cliproxyapi/          # 后端配置和数据
    │   ├── CLIProxyAPI/     # 后端源码
    │   │   └── cli-proxy-api # 编译后的二进制
    │   ├── config.yaml      # 后端配置文件
    │   ├── auths/           # 认证数据目录
    │   └── logs/            # 日志目录
    ├── cpamc/               # 前端源码
    │   └── dist/            # 构建产物
    └── cpamc-dist/          # Nginx 服务的静态文件目录
```

## 日常维护

### New API 服务管理

```bash
# 查看运行状态
systemctl status new-api

# 查看实时日志
journalctl -u new-api -f

# 重启服务
systemctl restart new-api

# 停止服务
systemctl stop new-api

# 开机自启
systemctl enable new-api
```

**更新版本：**

```bash
cd /aiproxy/new-api/new-api
git pull
cd server && go build -o new-api . && cd ..
cd web && npm install && npm run build && cd ..
systemctl restart new-api
```

### CLIProxyAPI 后端服务管理

```bash
# 查看运行状态
systemctl status cli-proxy-api

# 查看实时日志
journalctl -u cli-proxy-api -f

# 重启服务
systemctl restart cli-proxy-api

# 停止服务
systemctl stop cli-proxy-api

# 开机自启
systemctl enable cli-proxy-api

# 查看管理密钥
grep 'secret-key' /aiproxy/cpa/cliproxyapi/config.yaml
```

**更新版本：**

```bash
cd /aiproxy/cpa/cliproxyapi/CLIProxyAPI
git pull
go build -o cli-proxy-api .
systemctl restart cli-proxy-api
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

```bash
# 手动续期
certbot renew

# 测试续期（不会真的续期）
certbot renew --dry-run
```

## 常见问题

### 1. 部署失败怎么办？

查看对应步骤的错误信息，可以通过以下命令排查：

```bash
# 查看 New API 日志
journalctl -u new-api -f

# 查看 CLIProxyAPI 日志
journalctl -u cli-proxy-api -f

# 查看 Nginx 错误日志
tail -f /var/log/nginx/error.log
```

### 2. 编译失败怎么办？

确保服务器有足够的内存和磁盘空间：

```bash
# 检查内存
free -h

# 检查磁盘空间
df -h
```

如果内存不足（< 2GB），可以增加 swap：

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

### 3. 无法访问管理后台？

- 检查防火墙是否放行相应端口：`ufw status`
- 检查服务是否正常运行：`systemctl status new-api` 和 `systemctl status cli-proxy-api`
- 检查 Nginx 状态：`systemctl status nginx`
- 如果是域名访问，确认 DNS 解析是否生效

### 4. Go 编译失败？

确保 Go 版本 >= 1.21：

```bash
go version
```

如果版本过低，可能需要重新安装或设置 PATH：

```bash
export PATH=$PATH:/usr/local/go/bin
go version
```

### 5. CPA 管理面板连接失败？

- 确认 CLIProxyAPI 服务正在运行：`systemctl status cli-proxy-api`
- 确认管理密钥正确：`grep 'secret-key' /aiproxy/cpa/cliproxyapi/config.yaml`
- 检查 Nginx 反代配置是否正确
- 查看后端日志：`journalctl -u cli-proxy-api -f`

## 项目结构

```
.
├── README.md               # 项目说明文档（本文件）
└── deploy-no-docker.sh     # 无 Docker 版一键部署脚本
```

## 技术栈

- **部署脚本**：Bash
- **AI API 网关**：New API (Go + React)
- **CLI API 代理**：CLIProxyAPI (Go)
- **管理前端**：CPAMC (React + TypeScript + Vite + Bun)
- **反向代理**：Nginx
- **SSL 证书**：Let's Encrypt (Certbot)
- **进程管理**：systemd
- **运行环境**：Go 1.22 + Node.js 20 + Bun

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

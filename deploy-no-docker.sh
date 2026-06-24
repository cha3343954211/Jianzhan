#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/aiproxy"

NEW_API_DIR="$INSTALL_DIR/new-api"
NEW_API_PORT=3000

CPA_DIR="$INSTALL_DIR/cpa"
CLI_PROXY_DIR="$CPA_DIR/cliproxyapi"
CLI_PROXY_CONFIG="$CLI_PROXY_DIR/config.yaml"
CLI_PROXY_AUTH_DIR="$CLI_PROXY_DIR/auths"
CLI_PROXY_LOG_DIR="$CPA_DIR/logs"
CLI_PROXY_PORT=8317
CPAMC_DIR="$CPA_DIR/cpamc"
CPAMC_SERVE_DIR="$CPA_DIR/cpamc-dist"

SCRIPT_VERSION="2.0.0"

logo() {
    echo -e "${BLUE}"
    echo "  _____    _____    _____    _____   __  __   ___   __   __ "
    echo " |_   _|  |  __ \\  |  __ \\  / ____| |  \\/  | |__ \\  \\ \\ / / "
    echo "   | |    | |__) | | |__) || |      | \\  / |    ) |  \\ V /  "
    echo "   | |    |  ___/  |  _  / | |      | |\\/| |   / /    > <   "
    echo "  _| |_   | |      | | \\ \\ | |____  | |  | |  / /_   / . \\  "
    echo " |_____|  |_|      |_|  \\_\\ \\_____| |_|  |_| |____| /_/ \\_\\ "
    echo ""
    echo -e "   AI Proxy 一键部署脚本（无 Docker 版）v${SCRIPT_VERSION}"
    echo -e "   源码编译部署：New API + CLIProxyAPI + CPAMC"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo -e "${RED}无法检测操作系统版本${NC}"
        exit 1
    fi

    if [[ "$OS" != *"Ubuntu"* ]] && [[ "$OS" != *"Debian"* ]]; then
        echo -e "${YELLOW}警告：此脚本专为 Ubuntu/Debian 设计，当前系统为 $OS，可能会有问题${NC}"
        read -p "是否继续？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    echo -e "${GREEN}操作系统检测通过: $OS $VER${NC}"
}

install_dependencies() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 1/9: 安装系统依赖${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}更新软件包列表...${NC}"
    apt-get update -qq

    echo -e "${YELLOW}安装基础工具和编译依赖...${NC}"
    apt-get install -y -qq curl wget git nginx certbot python3-certbot-nginx ufw \
        sqlite3 libsqlite3-dev build-essential unzip > /dev/null 2>&1

    echo -e "${GREEN}系统依赖安装完成${NC}"
}

install_go() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 2/9: 安装 Go 环境${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v go &> /dev/null; then
        GO_VERSION=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
        echo -e "${GREEN}Go 已安装: $(go version)${NC}"
        if [[ "$(echo "$GO_VERSION" | cut -d. -f1)" -lt 1 ]] || \
           [[ "$GO_VERSION" < "1.21" ]]; then
            echo -e "${YELLOW}Go 版本过低（需要 1.21+），将重新安装...${NC}"
            GO_INSTALLED=false
        else
            GO_INSTALLED=true
        fi
    else
        GO_INSTALLED=false
    fi

    if [ "$GO_INSTALLED" = false ]; then
        echo -e "${YELLOW}正在安装 Go 1.22...${NC}"
        curl -fsSL https://go.dev/dl/go1.22.5.linux-amd64.tar.gz -o /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin
        echo -e "${GREEN}Go 安装完成: $(/usr/local/go/bin/go version)${NC}"
    fi
}

install_nodejs() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 3/9: 安装 Node.js 环境${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | grep -oP 'v\K[0-9]+')
        echo -e "${GREEN}Node.js 已安装: $(node -v)${NC}"
        if [ "$NODE_VERSION" -lt 18 ]; then
            echo -e "${YELLOW}Node.js 版本过低（需要 18+），将重新安装...${NC}"
            NODE_INSTALLED=false
        else
            NODE_INSTALLED=true
        fi
    else
        NODE_INSTALLED=false
    fi

    if [ "$NODE_INSTALLED" = false ]; then
        echo -e "${YELLOW}正在安装 Node.js 20...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
        apt-get install -y -qq nodejs > /dev/null 2>&1
        echo -e "${GREEN}Node.js 安装完成: $(node -v)${NC}"
    fi
}

install_bun() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 4/9: 安装 Bun 运行时${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v bun &> /dev/null; then
        echo -e "${GREEN}Bun 已安装: $(bun --version)${NC}"
        bun upgrade 2>/dev/null || echo -e "${YELLOW}Bun 更新失败，继续使用当前版本${NC}"
    else
        echo -e "${YELLOW}正在安装 Bun...${NC}"
        curl -fsSL https://bun.sh/install | bash > /dev/null 2>&1
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
        echo -e "${GREEN}Bun 安装完成: $(bun --version)${NC}"
    fi
}

prompt_domains() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  域名配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}请配置两个域名（需要已解析到本服务器，可留空跳过）${NC}"
    echo -e "${YELLOW}1. New API 域名 - AI API 网关${NC}"
    echo -e "${YELLOW}2. CPA 管理系统域名 - CLI Proxy API 管理面板${NC}"
    echo ""

    read -p "请输入 New API 域名（如 api.example.com，留空用 IP:端口访问）: " NEW_API_DOMAIN
    read -p "请输入 CPA 管理系统域名（如 cpa.example.com，留空用 IP 访问）: " CPA_DOMAIN

    echo ""
    echo -e "${GREEN}请确认以下配置信息：${NC}"
    echo "----------------------------------------"
    echo -e "  New API 域名:      ${BLUE}${NEW_API_DOMAIN:-未配置（使用 IP:端口访问）}${NC}"
    echo -e "  CPA 管理系统域名:  ${BLUE}${CPA_DOMAIN:-未配置（使用 IP 访问）}${NC}"
    echo -e "  安装目录:          ${BLUE}$INSTALL_DIR${NC}"
    echo "----------------------------------------"
    echo ""

    read -p "确认以上配置是否正确？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}请重新运行脚本进行配置${NC}"
        exit 0
    fi
}

generate_secret() {
    local length=${1:-32}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

generate_cpa_config() {
    if [ -f "$CLI_PROXY_CONFIG" ]; then
        echo -e "${YELLOW}CPA 配置文件已存在，跳过生成${NC}"
        return
    fi

    echo -e "${YELLOW}生成 CLIProxyAPI 配置文件...${NC}"

    mkdir -p "$CLI_PROXY_DIR"
    mkdir -p "$CLI_PROXY_AUTH_DIR"
    mkdir -p "$CLI_PROXY_LOG_DIR"

    local SECRET_KEY
    SECRET_KEY=$(generate_secret 32)

    cat > "$CLI_PROXY_CONFIG" << EOF
host: "127.0.0.1"
port: $CLI_PROXY_PORT

tls:
  enable: false
  cert: ""
  key: ""

remote-management:
  allow-remote: true
  secret-key: "$SECRET_KEY"
  disable-control-panel: false

auth-dir: "$CLI_PROXY_AUTH_DIR"

api-keys: []

debug: false
logging-to-file: true
logs-max-total-size-mb: 500
error-logs-max-files: 10

usage-statistics-enabled: true
redis-usage-queue-retention-seconds: 60

proxy-url: ""
request-retry: 3
max-retry-credentials: 0
max-retry-interval: 30
disable-cooling: false
commercial-mode: false

quota-exceeded:
  switch-project: true
  switch-preview-model: true
  antigravity-credits: true

routing:
  strategy: "round-robin"
  session-affinity: false
  session-affinity-ttl: "1h"

ws-auth: true
enable-gemini-cli-endpoint: false
force-model-prefix: false
passthrough-headers: false
disable-image-generation: false
disable-claude-cloak-mode: false

codex:
  identity-confuse: false

nonstream-keepalive-interval: 0

plugins:
  enabled: false
  dir: "plugins"
  configs:
    example:
      enabled: true
      priority: 1
      config1: true
      config2: "string"
      config3: 3
      mode: "safe"
EOF

    echo -e "${GREEN}配置文件已生成: $CLI_PROXY_CONFIG${NC}"
}

deploy_new_api() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 5/9: 部署 New API${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    export PATH=$PATH:/usr/local/go/bin

    mkdir -p "$NEW_API_DIR"
    mkdir -p "$NEW_API_DIR/data"
    echo -e "${GREEN}创建 New API 目录: $NEW_API_DIR${NC}"

    if [ -d "$NEW_API_DIR/new-api" ]; then
        echo -e "${YELLOW}New API 源码目录已存在，更新中...${NC}"
        (
            cd "$NEW_API_DIR/new-api"
            git pull > /dev/null 2>&1
        )
    else
        echo -e "${YELLOW}克隆 New API 仓库...${NC}"
        git clone https://github.com/QuantumNous/new-api.git "$NEW_API_DIR/new-api" > /dev/null 2>&1
    fi

    echo -e "${YELLOW}安装后端依赖...${NC}"
    (
        cd "$NEW_API_DIR/new-api/server"
        go mod download > /dev/null 2>&1
    )

    echo -e "${YELLOW}安装前端依赖...${NC}"
    (
        cd "$NEW_API_DIR/new-api/web"
        npm install --silent > /dev/null 2>&1
    )

    echo -e "${YELLOW}构建前端...${NC}"
    (
        cd "$NEW_API_DIR/new-api/web"
        npm run build > /dev/null 2>&1
    )

    echo -e "${YELLOW}构建后端...${NC}"
    (
        cd "$NEW_API_DIR/new-api/server"
        go build -o new-api . > /dev/null 2>&1
    )

    if [ ! -f "$NEW_API_DIR/new-api/server/new-api" ]; then
        echo -e "${RED}New API 后端编译失败${NC}"
        exit 1
    fi

    echo -e "${GREEN}New API 编译完成${NC}"

    cat > /etc/systemd/system/new-api.service << 'SYSTEMD_EOF'
[Unit]
Description=New API Service
After=network.target

[Service]
Type=simple
WorkingDirectory=INSTALL_DIR_PLACEHOLDER/new-api/server
ExecStart=INSTALL_DIR_PLACEHOLDER/new-api/server/new-api
Restart=unless-stopped
RestartSec=5
Environment=TZ=Asia/Shanghai

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    sed -i "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" /etc/systemd/system/new-api.service

    systemctl daemon-reload
    systemctl enable new-api > /dev/null 2>&1
    systemctl start new-api

    sleep 5

    if systemctl is-active --quiet new-api; then
        echo -e "${GREEN}New API 部署成功${NC}"
    else
        echo -e "${RED}New API 启动失败，请检查日志: journalctl -u new-api${NC}"
        exit 1
    fi
}

deploy_cpa_backend() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 6/9: 部署 CLIProxyAPI 后端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    export PATH=$PATH:/usr/local/go/bin

    generate_cpa_config

    mkdir -p "$CLI_PROXY_DIR"

    if [ -d "$CLI_PROXY_DIR/CLIProxyAPI" ]; then
        echo -e "${YELLOW}CLIProxyAPI 源码目录已存在，更新中...${NC}"
        (
            cd "$CLI_PROXY_DIR/CLIProxyAPI"
            git pull > /dev/null 2>&1
        )
    else
        echo -e "${YELLOW}克隆 CLIProxyAPI 仓库...${NC}"
        git clone https://github.com/router-for-me/CLIProxyAPI.git "$CLI_PROXY_DIR/CLIProxyAPI" > /dev/null 2>&1
    fi

    echo -e "${YELLOW}编译 CLIProxyAPI...${NC}"
    (
        cd "$CLI_PROXY_DIR/CLIProxyAPI"
        go build -o cli-proxy-api . > /dev/null 2>&1
    )

    if [ ! -f "$CLI_PROXY_DIR/CLIProxyAPI/cli-proxy-api" ]; then
        echo -e "${RED}CLIProxyAPI 编译失败${NC}"
        exit 1
    fi

    echo -e "${GREEN}CLIProxyAPI 编译完成${NC}"

    cat > /etc/systemd/system/cli-proxy-api.service << 'SYSTEMD_EOF'
[Unit]
Description=CLI Proxy API Service
After=network.target

[Service]
Type=simple
WorkingDirectory=CLI_PROXY_DIR_PLACEHOLDER/CLIProxyAPI
ExecStart=CLI_PROXY_DIR_PLACEHOLDER/CLIProxyAPI/cli-proxy-api
Restart=unless-stopped
RestartSec=5
Environment=TZ=Asia/Shanghai

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    sed -i "s|CLI_PROXY_DIR_PLACEHOLDER|$CLI_PROXY_DIR|g" /etc/systemd/system/cli-proxy-api.service

    systemctl daemon-reload
    systemctl enable cli-proxy-api > /dev/null 2>&1
    systemctl start cli-proxy-api

    sleep 5

    if systemctl is-active --quiet cli-proxy-api; then
        echo -e "${GREEN}CLIProxyAPI 后端部署成功${NC}"
    else
        echo -e "${RED}CLIProxyAPI 启动失败，请检查日志: journalctl -u cli-proxy-api${NC}"
        exit 1
    fi
}

deploy_cpa_frontend() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 7/9: 部署 CPAMC 管理前端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    if [ -d "$CPAMC_DIR" ]; then
        echo -e "${YELLOW}CPAMC 目录已存在，更新源码...${NC}"
        (
            cd "$CPAMC_DIR"
            git pull > /dev/null 2>&1
        )
    else
        echo -e "${YELLOW}克隆 CPAMC 仓库...${NC}"
        git clone https://github.com/router-for-me/Cli-Proxy-API-Management-Center.git "$CPAMC_DIR" > /dev/null 2>&1
    fi

    echo -e "${YELLOW}安装依赖...${NC}"
    (
        cd "$CPAMC_DIR"
        bun install --frozen-lockfile > /dev/null 2>&1
    )

    echo -e "${YELLOW}构建前端...${NC}"
    (
        cd "$CPAMC_DIR"
        bun run build > /dev/null 2>&1
    )

    if [ -f "$CPAMC_DIR/dist/index.html" ]; then
        echo -e "${GREEN}CPAMC 前端构建成功${NC}"
    else
        echo -e "${RED}CPAMC 前端构建失败${NC}"
        exit 1
    fi

    rm -rf "$CPAMC_SERVE_DIR"
    mkdir -p "$CPAMC_SERVE_DIR"
    cp "$CPAMC_DIR/dist/index.html" "$CPAMC_SERVE_DIR/index.html"

    echo -e "${GREEN}CPAMC 前端部署完成${NC}"
}

configure_nginx() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 8/9: 配置 Nginx${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    systemctl stop nginx 2>/dev/null || true

    # ---- New API Nginx 配置（仅当配置了域名时） ----
    if [ -n "$NEW_API_DOMAIN" ]; then
        echo -e "${YELLOW}New API 域名: $NEW_API_DOMAIN${NC}"

        cat > /etc/nginx/sites-available/new-api << 'NGINX_EOF'
server {
    listen 80;
    server_name NEW_API_DOMAIN_PLACEHOLDER;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:NEW_API_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
    }
}
NGINX_EOF

        sed -i "s/NEW_API_DOMAIN_PLACEHOLDER/$NEW_API_DOMAIN/g" /etc/nginx/sites-available/new-api
        sed -i "s/NEW_API_PORT_PLACEHOLDER/$NEW_API_PORT/g" /etc/nginx/sites-available/new-api

        ln -sf /etc/nginx/sites-available/new-api /etc/nginx/sites-enabled/new-api
    else
        echo -e "${YELLOW}New API: 未配置域名，直接使用 $NEW_API_PORT 端口访问${NC}"
        rm -f /etc/nginx/sites-enabled/new-api
    fi

    # ---- CPA Nginx 配置（前端 + 后端反代） ----
    if [ -n "$CPA_DOMAIN" ]; then
        CPA_SERVER_NAME="$CPA_DOMAIN"
        echo -e "${YELLOW}CPA 域名: $CPA_DOMAIN${NC}"
    else
        CPA_SERVER_NAME="_"
        echo -e "${YELLOW}CPA: 未配置域名，使用 IP 访问${NC}"
    fi

    cat > /etc/nginx/sites-available/cpa << 'NGINX_EOF'
server {
    listen 80;
    server_name CPA_SERVER_NAME_PLACEHOLDER;

    client_max_body_size 100M;

    location = / {
        root CPAMC_SERVE_DIR_PLACEHOLDER;
        index index.html;
    }

    location / {
        proxy_pass http://127.0.0.1:CLI_PROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
    }
}
NGINX_EOF

    sed -i "s/CPA_SERVER_NAME_PLACEHOLDER/$CPA_SERVER_NAME/g" /etc/nginx/sites-available/cpa
    sed -i "s|CPAMC_SERVE_DIR_PLACEHOLDER|$CPAMC_SERVE_DIR|g" /etc/nginx/sites-available/cpa
    sed -i "s/CLI_PROXY_PORT_PLACEHOLDER/$CLI_PROXY_PORT/g" /etc/nginx/sites-available/cpa

    ln -sf /etc/nginx/sites-available/cpa /etc/nginx/sites-enabled/cpa
    rm -f /etc/nginx/sites-enabled/default

    nginx -t > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        systemctl start nginx
        systemctl enable nginx > /dev/null 2>&1
        echo -e "${GREEN}Nginx 配置成功并已启动${NC}"
    else
        echo -e "${RED}Nginx 配置失败，请检查配置文件${NC}"
        nginx -t
        exit 1
    fi
}

setup_firewall() {
    echo ""
    echo -e "${YELLOW}配置防火墙...${NC}"

    ufw --force reset > /dev/null 2>&1 || true
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow "$NEW_API_PORT/tcp" > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo -e "${GREEN}防火墙配置完成（已放行 22/80/443/$NEW_API_PORT 端口）${NC}"
}

setup_ssl() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 9/9: SSL 证书配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if [ -n "$NEW_API_DOMAIN" ]; then
        read -p "是否为 New API 配置 SSL 证书？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}配置 New API SSL 证书...${NC}"
            certbot --nginx -d "$NEW_API_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null || \
                echo -e "${YELLOW}New API SSL 证书申请失败，请稍后手动配置${NC}"
        fi
    else
        echo -e "${YELLOW}New API 未配置域名，跳过 SSL${NC}"
    fi

    if [ -n "$CPA_DOMAIN" ]; then
        read -p "是否为 CPA 管理系统配置 SSL 证书？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}配置 CPA SSL 证书...${NC}"
            certbot --nginx -d "$CPA_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null || \
                echo -e "${YELLOW}CPA SSL 证书申请失败，请稍后手动配置${NC}"
        fi
    else
        echo -e "${YELLOW}CPA 未配置域名，跳过 SSL${NC}"
    fi

    echo -e "${GREEN}SSL 证书配置完成${NC}"
}

get_server_ip() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    echo "$SERVER_IP"
}

get_cpa_secret_key() {
    if [ -f "$CLI_PROXY_CONFIG" ]; then
        grep 'secret-key:' "$CLI_PROXY_CONFIG" | head -1 | sed 's/.*secret-key: *"//' | sed 's/"//'
    else
        echo "未生成"
    fi
}

show_summary() {
    local SERVER_IP
    SERVER_IP=$(get_server_ip)
    local CPA_SECRET_KEY
    CPA_SECRET_KEY=$(get_cpa_secret_key)

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${BLUE}【访问地址】${NC}"
    echo "----------------------------------------"

    if [ -n "$NEW_API_DOMAIN" ]; then
        echo -e "  New API:           ${GREEN}https://$NEW_API_DOMAIN${NC}"
    else
        echo -e "  New API:           ${GREEN}http://$SERVER_IP:$NEW_API_PORT${NC}"
    fi

    if [ -n "$CPA_DOMAIN" ]; then
        echo -e "  CPA 管理系统:      ${GREEN}https://$CPA_DOMAIN${NC}"
    else
        echo -e "  CPA 管理系统:      ${GREEN}http://$SERVER_IP${NC}"
    fi

    echo "----------------------------------------"
    echo ""
    echo -e "${BLUE}【New API 默认账号】${NC}"
    echo -e "  用户名: ${YELLOW}root${NC}"
    echo -e "  密  码: ${YELLOW}123456${NC}"
    echo -e "  ${RED}请登录后立即修改默认密码！${NC}"
    echo ""
    echo -e "${BLUE}【CPA 管理密钥】${NC}"
    echo -e "  管理密钥: ${YELLOW}$CPA_SECRET_KEY${NC}"
    echo -e "  ${RED}请妥善保存此密钥，登录 CPA 管理面板时需要输入！${NC}"
    echo ""
    echo -e "${BLUE}【安装目录】${NC}"
    echo -e "  主目录:            $INSTALL_DIR"
    echo -e "  New API 源码:      $NEW_API_DIR/new-api"
    echo -e "  New API 数据:      $NEW_API_DIR/data/"
    echo -e "  CPA 后端源码:      $CLI_PROXY_DIR/CLIProxyAPI"
    echo -e "  CPA 配置:          $CLI_PROXY_CONFIG"
    echo -e "  CPA 认证目录:      $CLI_PROXY_AUTH_DIR"
    echo -e "  CPA 前端源码:      $CPAMC_DIR"
    echo -e "  CPA 前端静态文件:  $CPAMC_SERVE_DIR"
    echo ""
}

show_maintenance() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  后期维护与更新操作指南${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${YELLOW}【New API 服务管理】${NC}"
    echo -e "  查看状态:    ${GREEN}systemctl status new-api${NC}"
    echo -e "  查看日志:    ${GREEN}journalctl -u new-api -f${NC}"
    echo -e "  重启服务:    ${GREEN}systemctl restart new-api${NC}"
    echo -e "  停止服务:    ${GREEN}systemctl stop new-api${NC}"
    echo -e "  开机自启:    ${GREEN}systemctl enable new-api${NC}"
    echo ""
    echo -e "  更新版本:"
    echo -e "    ${GREEN}cd $NEW_API_DIR/new-api${NC}"
    echo -e "    ${GREEN}git pull${NC}"
    echo -e "    ${GREEN}cd server && go build -o new-api . && cd ..${NC}"
    echo -e "    ${GREEN}cd web && npm install && npm run build && cd ..${NC}"
    echo -e "    ${GREEN}systemctl restart new-api${NC}"
    echo ""
    echo -e "${YELLOW}【CLIProxyAPI 后端服务管理】${NC}"
    echo -e "  查看状态:    ${GREEN}systemctl status cli-proxy-api${NC}"
    echo -e "  查看日志:    ${GREEN}journalctl -u cli-proxy-api -f${NC}"
    echo -e "  重启服务:    ${GREEN}systemctl restart cli-proxy-api${NC}"
    echo -e "  停止服务:    ${GREEN}systemctl stop cli-proxy-api${NC}"
    echo -e "  开机自启:    ${GREEN}systemctl enable cli-proxy-api${NC}"
    echo ""
    echo -e "  更新版本:"
    echo -e "    ${GREEN}cd $CLI_PROXY_DIR/CLIProxyAPI${NC}"
    echo -e "    ${GREEN}git pull${NC}"
    echo -e "    ${GREEN}go build -o cli-proxy-api .${NC}"
    echo -e "    ${GREEN}systemctl restart cli-proxy-api${NC}"
    echo ""
    echo -e "${YELLOW}【CPAMC 前端维护】${NC}"
    echo -e "  更新到最新版本:"
    echo -e "    ${GREEN}cd $CPAMC_DIR${NC}"
    echo -e "    ${GREEN}git pull${NC}"
    echo -e "    ${GREEN}bun install --frozen-lockfile${NC}"
    echo -e "    ${GREEN}bun run build${NC}"
    echo -e "    ${GREEN}cp dist/index.html $CPAMC_SERVE_DIR/index.html${NC}"
    echo ""
    echo -e "${YELLOW}【Nginx 维护】${NC}"
    echo -e "  测试配置:    ${GREEN}nginx -t${NC}"
    echo -e "  重载配置:    ${GREEN}systemctl reload nginx${NC}"
    echo -e "  重启服务:    ${GREEN}systemctl restart nginx${NC}"
    echo ""
    echo -e "${YELLOW}【SSL 证书续期】${NC}"
    echo -e "  手动续期:    ${GREEN}certbot renew${NC}"
    echo -e "  测试续期:    ${GREEN}certbot renew --dry-run${NC}"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！感谢使用 AI Proxy 一键部署脚本${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
}

main() {
    clear
    logo
    check_root
    check_os

    echo ""
    echo -e "${YELLOW}即将在服务器上部署以下项目（全部源码编译，无需 Docker）：${NC}"
    echo -e "  1. New API - AI API 网关（Go + React）"
    echo -e "  2. CLIProxyAPI - CLI API 代理后端（Go）"
    echo -e "  3. CPAMC - CLI Proxy API 管理前端（React + Bun）"
    echo -e "  4. Nginx 反向代理 + SSL 证书"
    echo ""
    echo -e "${YELLOW}注意：此脚本无需 Docker，首次部署耗时较长（约 10-30 分钟）${NC}"
    echo ""
    read -p "是否继续部署？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}部署已取消${NC}"
        exit 0
    fi

    prompt_domains
    install_dependencies
    install_go
    install_nodejs
    install_bun
    deploy_new_api
    deploy_cpa_backend
    deploy_cpa_frontend
    configure_nginx
    setup_firewall
    setup_ssl
    show_summary
    show_maintenance
}

main "$@"

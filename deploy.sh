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
CLI_PROXY_LOG_DIR="$CLI_PROXY_DIR/logs"
CPAMC_DIR="$CPA_DIR/cpamc"
CPAMC_SERVE_DIR="$CPA_DIR/cpamc-dist"
CLI_PROXY_PORT=8317

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
    echo -e "   AI Proxy 一键部署脚本 v${SCRIPT_VERSION}"
    echo -e "   New API + CLI Proxy API + CPAMC 管理面板"
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
    echo -e "${BLUE}  步骤 1/8: 安装系统依赖${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}更新软件包列表...${NC}"
    apt-get update -qq

    echo -e "${YELLOW}安装基础工具...${NC}"
    apt-get install -y -qq curl wget git nginx certbot python3-certbot-nginx ufw sqlite3 > /dev/null 2>&1

    echo -e "${GREEN}系统依赖安装完成${NC}"
}

install_docker() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 2/8: 安装 Docker${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装: $(docker --version)${NC}"
    else
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        systemctl start docker
        systemctl enable docker
        echo -e "${GREEN}Docker 安装完成: $(docker --version)${NC}"
    fi
}

install_bun() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 3/8: 安装 Bun 运行时${NC}"
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

    echo -e "${YELLOW}请配置两个域名（需要已解析到本服务器）${NC}"
    echo -e "${YELLOW}1. New API 域名 - AI API 网关${NC}"
    echo -e "${YELLOW}2. CPA 管理系统域名 - CLI Proxy API 管理面板${NC}"
    echo ""

    read -p "请输入 New API 域名（如 api.example.com，可留空用 IP 访问）: " NEW_API_DOMAIN
    read -p "请输入 CPA 管理系统域名（如 cpa.example.com，可留空用 IP 访问）: " CPA_DOMAIN

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

deploy_new_api() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 4/8: 部署 New API${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    mkdir -p "$NEW_API_DIR/data"
    echo -e "${GREEN}创建 New API 目录: $NEW_API_DIR${NC}"

    echo -e "${YELLOW}拉取 New API 镜像...${NC}"
    docker pull calciumion/new-api:latest > /dev/null 2>&1

    if docker ps -a --format '{{.Names}}' | grep -q '^new-api$'; then
        echo -e "${YELLOW}已存在 new-api 容器，更新中...${NC}"
        docker stop new-api > /dev/null 2>&1
        docker rm new-api > /dev/null 2>&1
    fi

    if [ -n "$NEW_API_DOMAIN" ]; then
        BIND_ADDR="127.0.0.1"
        echo -e "${YELLOW}已配置域名，New API 仅监听本地，由 Nginx 反向代理${NC}"
    else
        BIND_ADDR="0.0.0.0"
        echo -e "${YELLOW}未配置域名，New API 直接暴露 3000 端口${NC}"
    fi

    echo -e "${YELLOW}启动 New API 容器...${NC}"
    docker run --name new-api -d --restart unless-stopped \
        -p "$BIND_ADDR:$NEW_API_PORT:3000" \
        -v "$NEW_API_DIR/data:/data" \
        -e TZ=Asia/Shanghai \
        calciumion/new-api:latest > /dev/null 2>&1

    sleep 5

    if docker ps --format '{{.Names}}' | grep -q '^new-api$'; then
        echo -e "${GREEN}New API 部署成功${NC}"
    else
        echo -e "${RED}New API 启动失败，请检查日志: docker logs new-api${NC}"
        exit 1
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

    local SECRET_KEY
    SECRET_KEY=$(generate_secret 32)

    mkdir -p "$CLI_PROXY_DIR"
    mkdir -p "$CLI_PROXY_AUTH_DIR"
    mkdir -p "$CLI_PROXY_LOG_DIR"

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

deploy_cpa_backend() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 5/8: 部署 CLIProxyAPI 后端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    generate_cpa_config

    echo -e "${YELLOW}拉取 CLIProxyAPI 镜像...${NC}"
    docker pull eceasy/cli-proxy-api:latest > /dev/null 2>&1

    if docker ps -a --format '{{.Names}}' | grep -q '^cli-proxy-api$'; then
        echo -e "${YELLOW}已存在 cli-proxy-api 容器，更新中...${NC}"
        docker stop cli-proxy-api > /dev/null 2>&1
        docker rm cli-proxy-api > /dev/null 2>&1
    fi

    echo -e "${YELLOW}启动 CLIProxyAPI 容器...${NC}"
    docker run --name cli-proxy-api -d --restart unless-stopped \
        -p "127.0.0.1:$CLI_PROXY_PORT:$CLI_PROXY_PORT" \
        -v "$CLI_PROXY_CONFIG:/CLIProxyAPI/config.yaml" \
        -v "$CLI_PROXY_AUTH_DIR:/root/.cli-proxy-api" \
        -v "$CLI_PROXY_LOG_DIR:/CLIProxyAPI/logs" \
        -e TZ=Asia/Shanghai \
        eceasy/cli-proxy-api:latest > /dev/null 2>&1

    sleep 5

    if docker ps --format '{{.Names}}' | grep -q '^cli-proxy-api$'; then
        echo -e "${GREEN}CLIProxyAPI 后端部署成功${NC}"
    else
        echo -e "${RED}CLIProxyAPI 启动失败，请检查日志: docker logs cli-proxy-api${NC}"
        exit 1
    fi
}

deploy_cpa_frontend() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 6/8: 部署 CPAMC 管理前端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    if [ -d "$CPAMC_DIR" ]; then
        echo -e "${YELLOW}CPAMC 目录已存在，更新源码...${NC}"
        cd "$CPAMC_DIR"
        git pull > /dev/null 2>&1
    else
        echo -e "${YELLOW}克隆 CPAMC 仓库...${NC}"
        git clone https://github.com/router-for-me/Cli-Proxy-API-Management-Center.git "$CPAMC_DIR" > /dev/null 2>&1
        cd "$CPAMC_DIR"
    fi

    echo -e "${YELLOW}安装依赖...${NC}"
    bun install --frozen-lockfile > /dev/null 2>&1

    echo -e "${YELLOW}构建前端...${NC}"
    bun run build > /dev/null 2>&1

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
    echo -e "${BLUE}  步骤 7/8: 配置 Nginx${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    systemctl stop nginx 2>/dev/null || true

    # ---- New API Nginx 配置（仅当配置了域名时） ----
    if [ -n "$NEW_API_DOMAIN" ]; then
        echo -e "${YELLOW}New API 域名: $NEW_API_DOMAIN${NC}"

        cat > /etc/nginx/sites-available/new-api << 'NGINX_EOF'
server {
    listen 80;
    server_name NEW_API_SERVER_NAME_PLACEHOLDER;

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

        sed -i "s/NEW_API_SERVER_NAME_PLACEHOLDER/$NEW_API_DOMAIN/g" /etc/nginx/sites-available/new-api
        sed -i "s/NEW_API_PORT_PLACEHOLDER/$NEW_API_PORT/g" /etc/nginx/sites-available/new-api

        ln -sf /etc/nginx/sites-available/new-api /etc/nginx/sites-enabled/new-api
    else
        echo -e "${YELLOW}New API: 未配置域名，直接使用 3000 端口访问${NC}"
        rm -f /etc/nginx/sites-enabled/new-api
    fi

    # ---- CPA Nginx 配置（前端 + 后端反代） ----
    if [ -z "$CPA_DOMAIN" ]; then
        CPA_SERVER_NAME="_"
        echo -e "${YELLOW}CPA: 未配置域名，使用 IP 访问${NC}"
    else
        CPA_SERVER_NAME="$CPA_DOMAIN"
        echo -e "${YELLOW}CPA 域名: $CPA_DOMAIN${NC}"
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
    ufw allow 3000/tcp > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo -e "${GREEN}防火墙配置完成（已放行 22/80/443/3000 端口）${NC}"
}

setup_ssl() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 8/8: SSL 证书配置${NC}"
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
    echo -e "  New API 数据:      $NEW_API_DIR/data/"
    echo -e "  CPA 后端配置:      $CLI_PROXY_CONFIG"
    echo -e "  CPA 认证目录:      $CLI_PROXY_AUTH_DIR"
    echo -e "  CPA 日志目录:      $CLI_PROXY_LOG_DIR"
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
    echo -e "${YELLOW}【New API 维护】${NC}"
    echo -e "  查看状态:    ${GREEN}docker ps | grep new-api${NC}"
    echo -e "  查看日志:    ${GREEN}docker logs -f new-api${NC}"
    echo -e "  重启服务:    ${GREEN}docker restart new-api${NC}"
    echo -e "  更新版本:    ${GREEN}docker pull calciumion/new-api:latest && docker restart new-api${NC}"
    echo ""
    echo -e "${YELLOW}【CLIProxyAPI 后端维护】${NC}"
    echo -e "  查看状态:    ${GREEN}docker ps | grep cli-proxy-api${NC}"
    echo -e "  查看日志:    ${GREEN}docker logs -f cli-proxy-api${NC}"
    echo -e "  重启服务:    ${GREEN}docker restart cli-proxy-api${NC}"
    echo ""
    echo -e "  更新到最新版本:"
    echo -e "    ${GREEN}docker pull eceasy/cli-proxy-api:latest${NC}"
    echo -e "    ${GREEN}docker stop cli-proxy-api \&\& docker rm cli-proxy-api${NC}"
    echo -e "    ${GREEN}docker run --name cli-proxy-api -d --restart unless-stopped \\${NC}"
    echo -e "    ${GREEN}  -p 127.0.0.1:$CLI_PROXY_PORT:$CLI_PROXY_PORT \\${NC}"
    echo -e "    ${GREEN}  -v $CLI_PROXY_CONFIG:/CLIProxyAPI/config.yaml \\${NC}"
    echo -e "    ${GREEN}  -v $CLI_PROXY_AUTH_DIR:/root/.cli-proxy-api \\${NC}"
    echo -e "    ${GREEN}  -v $CLI_PROXY_LOG_DIR:/CLIProxyAPI/logs \\${NC}"
    echo -e "    ${GREEN}  -e TZ=Asia/Shanghai \\${NC}"
    echo -e "    ${GREEN}  eceasy/cli-proxy-api:latest${NC}"
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
    echo -e "${YELLOW}【配置修改】${NC}"
    echo -e "  New API: 容器内 /data 目录挂载到 $NEW_API_DIR/data"
    echo -e "  CPA 配置: ${GREEN}vim $CLI_PROXY_CONFIG${NC}"
    echo -e "  CPA 重启: ${GREEN}docker restart cli-proxy-api${NC}"
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
    echo -e "${YELLOW}即将在服务器上部署以下项目：${NC}"
    echo -e "  1. New API - AI API 网关（Docker 部署）"
    echo -e "  2. CLIProxyAPI - CLI API 代理后端（Docker 部署）"
    echo -e "  3. CPAMC - CLI Proxy API 管理前端（静态页面）"
    echo -e "  4. Nginx 反向代理 + SSL 证书"
    echo ""
    echo -e "${YELLOW}注意：CPA 前后端部署在同一域名下，自动连接，无需手动配置后端地址${NC}"
    echo ""
    read -p "是否继续部署？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}部署已取消${NC}"
        exit 0
    fi

    prompt_domains
    install_dependencies
    install_docker
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

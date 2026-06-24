#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/aiproxy/cpa"
CLI_PROXY_DIR="$INSTALL_DIR/cliproxyapi"
CLI_PROXY_CONFIG="$CLI_PROXY_DIR/config.yaml"
CLI_PROXY_AUTH_DIR="$CLI_PROXY_DIR/auths"
CLI_PROXY_LOG_DIR="$CLI_PROXY_DIR/logs"
CPAMC_DIR="$INSTALL_DIR/cpamc"
CPAMC_SERVE_DIR="$INSTALL_DIR/cpamc-dist"
CLI_PROXY_PORT=8317

SCRIPT_VERSION="1.0.0"

logo() {
    echo -e "${BLUE}"
    echo "   ____ _     ___      ____   _    ___ "
    echo "  / ___| |   |_ _|    |  _ \\ /_\\  / _ \\"
    echo " | |   | |    | |_____| |_) / _ \\| | | |"
    echo " | |___| |___ | |_____|  __/ ___ \\ |_| |"
    echo "  \\____|_____|___|    |_| /_/   \\_\\___/"
    echo ""
    echo -e "   CLI Proxy API 一键部署脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "   (后端 + 管理前端 + Nginx 反向代理)${NC}"
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
    echo -e "${BLUE}  步骤 1/7: 安装系统依赖${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}更新软件包列表...${NC}"
    apt-get update -qq

    echo -e "${YELLOW}安装基础工具...${NC}"
    apt-get install -y -qq curl wget git nginx certbot python3-certbot-nginx ufw > /dev/null 2>&1

    echo -e "${GREEN}系统依赖安装完成${NC}"
}

install_docker() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 2/7: 安装 Docker${NC}"
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
    echo -e "${BLUE}  步骤 3/7: 安装 Bun 运行时${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v bun &> /dev/null; then
        echo -e "${GREEN}Bun 已安装: $(bun --version)${NC}"
        echo -e "${YELLOW}尝试更新 Bun...${NC}"
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

generate_secret() {
    local length=${1:-32}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

prompt_domain() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  域名配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}请为 CPA 管理系统配置解析域名（例如：cpa.example.com）${NC}"
    echo -e "${YELLOW}后端和前端将部署在同一域名下，前端在根路径，后端 API 自动反代${NC}"
    echo ""

    read -p "请输入 CPA 管理系统的域名: " CPA_DOMAIN

    echo ""
    echo -e "${GREEN}请确认以下配置信息：${NC}"
    echo "----------------------------------------"
    echo -e "  CPA 管理系统域名:  ${BLUE}${CPA_DOMAIN:-未配置（使用 IP 访问）}${NC}"
    echo -e "  安装目录:          ${BLUE}$INSTALL_DIR${NC}"
    echo -e "  后端端口:          ${BLUE}$CLI_PROXY_PORT（内部，不对外暴露）${NC}"
    echo "----------------------------------------"
    echo ""

    read -p "确认以上配置是否正确？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}请重新运行脚本进行配置${NC}"
        exit 0
    fi
}

create_directories() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 4/7: 部署 CLIProxyAPI 后端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    mkdir -p "$CLI_PROXY_DIR"
    mkdir -p "$CLI_PROXY_AUTH_DIR"
    mkdir -p "$CLI_PROXY_LOG_DIR"
    echo -e "${GREEN}创建安装目录: $INSTALL_DIR${NC}"
}

generate_config() {
    if [ -f "$CLI_PROXY_CONFIG" ]; then
        echo -e "${YELLOW}配置文件已存在，跳过生成${NC}"
        return
    fi

    echo -e "${YELLOW}生成配置文件...${NC}"

    local SECRET_KEY
    SECRET_KEY=$(generate_secret 32)

    cat > "$CLI_PROXY_CONFIG" << EOF
# CLIProxyAPI Configuration
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
    echo -e "${GREEN}管理密钥已自动生成，请妥善保存${NC}"
}

deploy_backend() {
    echo ""
    echo -e "${YELLOW}部署 CLIProxyAPI 后端...${NC}"

    if [ ! -f "$CLI_PROXY_CONFIG" ]; then
        generate_config
    fi

    echo -e "${YELLOW}拉取 Docker 镜像...${NC}"
    docker pull eceasy/cli-proxy-api:latest > /dev/null 2>&1

    if docker ps -a --format '{{.Names}}' | grep -q '^cli-proxy-api$'; then
        echo -e "${YELLOW}已存在 cli-proxy-api 容器，更新中...${NC}"
        docker stop cli-proxy-api > /dev/null 2>&1
        docker rm cli-proxy-api > /dev/null 2>&1
    fi

    echo -e "${YELLOW}启动容器...${NC}"
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

deploy_frontend() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 5/7: 部署 CPAMC 管理前端${NC}"
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
    echo -e "${BLUE}  步骤 6/7: 配置 Nginx${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    systemctl stop nginx 2>/dev/null || true

    if [ -z "$CPA_DOMAIN" ]; then
        echo -e "${YELLOW}未配置域名，Nginx 仅监听 IP${NC}"
        SERVER_NAME="_"
    else
        SERVER_NAME="$CPA_DOMAIN"
        echo -e "${YELLOW}配置域名: $CPA_DOMAIN${NC}"
    fi

    cat > /etc/nginx/sites-available/cpa << 'NGINX_EOF'
server {
    listen 80;
    server_name SERVER_NAME_PLACEHOLDER;

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

    sed -i "s/SERVER_NAME_PLACEHOLDER/$SERVER_NAME/g" /etc/nginx/sites-available/cpa
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
    ufw --force enable > /dev/null 2>&1

    echo -e "${GREEN}防火墙配置完成（已放行 22/80/443 端口）${NC}"
}

setup_ssl() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 7/7: SSL 证书配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if [ -z "$CPA_DOMAIN" ]; then
        echo -e "${YELLOW}未配置域名，跳过 SSL 证书配置${NC}"
        return
    fi

    read -p "是否配置 SSL 证书（需要域名已解析到本服务器）？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    echo -e "${YELLOW}配置 SSL 证书...${NC}"
    certbot --nginx -d "$CPA_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null || \
        echo -e "${YELLOW}SSL 证书申请失败，请稍后手动配置${NC}"

    echo -e "${GREEN}SSL 证书配置完成${NC}"
}

get_server_ip() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    echo "$SERVER_IP"
}

get_secret_key() {
    if [ -f "$CLI_PROXY_CONFIG" ]; then
        grep 'secret-key:' "$CLI_PROXY_CONFIG" | head -1 | sed 's/.*secret-key: *"//' | sed 's/"//'
    else
        echo "未生成"
    fi
}

show_summary() {
    local SERVER_IP
    SERVER_IP=$(get_server_ip)
    local SECRET_KEY
    SECRET_KEY=$(get_secret_key)

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${BLUE}【访问地址】${NC}"
    echo "----------------------------------------"

    if [ -n "$CPA_DOMAIN" ]; then
        echo -e "  CPA 管理系统:    ${GREEN}https://$CPA_DOMAIN${NC}"
    else
        echo -e "  CPA 管理系统:    ${GREEN}http://$SERVER_IP${NC}"
    fi

    echo "----------------------------------------"
    echo ""
    echo -e "${BLUE}【管理员密钥】${NC}"
    echo -e "  管理密钥: ${YELLOW}$SECRET_KEY${NC}"
    echo -e "  ${RED}请妥善保存此密钥，登录管理面板时需要输入！${NC}"
    echo ""
    echo -e "${BLUE}【安装目录】${NC}"
    echo -e "  主目录:            $INSTALL_DIR"
    echo -e "  后端配置:          $CLI_PROXY_CONFIG"
    echo -e "  后端认证目录:      $CLI_PROXY_AUTH_DIR"
    echo -e "  后端日志目录:      $CLI_PROXY_LOG_DIR"
    echo -e "  前端源码:          $CPAMC_DIR"
    echo -e "  前端静态文件:      $CPAMC_SERVE_DIR"
    echo ""
    echo -e "${BLUE}【使用说明】${NC}"
    echo -e "  1. 打开上面的访问地址"
    echo -e "  2. 在 Connection 中输入管理密钥并连接"
    echo -e "  3. 在管理面板中配置 API 密钥、OAuth 等"
    echo ""
}

show_maintenance() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  后期维护与更新操作指南${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${YELLOW}【CLIProxyAPI 后端维护】${NC}"
    echo -e "  查看状态:    ${GREEN}docker ps | grep cli-proxy-api${NC}"
    echo -e "  查看日志:    ${GREEN}docker logs -f cli-proxy-api${NC}"
    echo -e "  重启服务:    ${GREEN}docker restart cli-proxy-api${NC}"
    echo -e "  停止服务:    ${GREEN}docker stop cli-proxy-api${NC}"
    echo -e "  启动服务:    ${GREEN}docker start cli-proxy-api${NC}"
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
    echo -e "  查看日志:    ${GREEN}tail -f /var/log/nginx/error.log${NC}"
    echo ""
    echo -e "${YELLOW}【SSL 证书续期】${NC}"
    echo -e "  手动续期:    ${GREEN}certbot renew${NC}"
    echo -e "  测试续期:    ${GREEN}certbot renew --dry-run${NC}"
    echo ""
    echo -e "${YELLOW}【配置修改】${NC}"
    echo -e "  编辑配置文件: ${GREEN}vim $CLI_PROXY_CONFIG${NC}"
    echo -e "  重启生效:    ${GREEN}docker restart cli-proxy-api${NC}"
    echo -e "  查看密钥:    ${GREEN}grep 'secret-key' $CLI_PROXY_CONFIG${NC}"
    echo ""
    echo -e "${YELLOW}【数据备份】${NC}"
    echo -e "  配置文件: $CLI_PROXY_CONFIG"
    echo -e "  认证数据: $CLI_PROXY_AUTH_DIR"
    echo -e "  备份命令: ${GREEN}cp -r $INSTALL_DIR /path/to/backup/cpa-\$(date +%Y%m%d)${NC}"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！感谢使用 CPA 一键部署脚本${NC}"
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
    echo -e "  1. CLIProxyAPI 后端（Docker 部署）"
    echo -e "  2. CPAMC 管理前端（静态页面）"
    echo -e "  3. Nginx 反向代理（同一域名整合前后端）"
    echo ""
    echo -e "${YELLOW}注意：前端与后端部署在同一域名下，自动连接，无需手动配置后端地址${NC}"
    echo ""
    read -p "是否继续部署？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}部署已取消${NC}"
        exit 0
    fi

    prompt_domain
    install_dependencies
    install_docker
    install_bun
    create_directories
    generate_config
    deploy_backend
    deploy_frontend
    configure_nginx
    setup_firewall
    setup_ssl
    show_summary
    show_maintenance
}

main "$@"

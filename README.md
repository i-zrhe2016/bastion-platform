# Bastion（Spring Boot Server + Rust Agent）

这是一个可运行的跳板机原型，分为两个服务：

- `bastion-server`（Java/Spring Boot）：注册中心 + 服务发现 + 一键连接接口
- `bastion-agent`（Rust）：安装在跳板机上，启动后自动注册并周期性心跳

> 设计约束：`bastion-server` 不提供前端页面，仅提供 HTTP API；连接通过命令行 CLI（`one-click-connect.sh`）完成。

## 核心能力

- Agent 自动注册：`POST /api/v1/agents/register`
- 注册响应下发 server SSH 公钥（可选，agent 自动写入 `authorized_keys`）
- 心跳续约：`POST /api/v1/agents/heartbeat`
- 服务发现：`GET /api/v1/agents`
- 一键连接：`POST /api/v1/connections/one-click`
  - server 返回一次性 token 和可直接执行的 SSH 命令

## 架构说明

1. 在跳板机节点安装并启动 `bastion-agent`。
2. agent 读取/生成持久化 `agentId`，采集主机名与 IP。
3. agent 启动时向 `bastion-server` 注册，之后定时发心跳。
4. server 维护在线节点（基于 TTL），实现服务发现。
5. 调用 one-click API，server 生成短期 token 与连接命令，客户端直接执行。

## 运行方式

### 1) Server（推荐：Docker Compose，无本机依赖）

只需要本机安装 Docker + Docker Compose，不需要安装 Java/Maven。

```bash
docker compose up --build -d
```

如需让 server 可直接 SSH 到 agent，请在启动前设置 server 公钥（建议）：

```bash
export BASTION_SERVER_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
docker compose up --build -d
```

默认端口：`8080`

检查服务：

```bash
curl http://127.0.0.1:8080/actuator/health
```

停止服务：

```bash
docker compose down
```

### 2) 安装 agent（推荐：直接下载预编译二进制）

无需安装 Rust/Cargo，直接下载最新构建的静态链接二进制：

```bash
curl -fsSL https://github.com/i-zrhe2016/bastion-platform/releases/download/latest/bastion-agent-x86_64-linux \
  -o bastion-agent && chmod +x bastion-agent
```

### 2b) 从源码构建 agent（可选）

```bash
cd bastion-agent
cargo build --release
```

### 3) 启动 server（本地 Maven，可选）

```bash
cd bastion-server
mvn spring-boot:run
```

默认端口：`8080`

### 4) 启动 agent（本地演示）

```bash
cd bastion-agent
./target/release/bastion-agent --spring.config.location=application.yml
```

> 默认 `application.yml` 已配置 `bastion.server.base-url: http://localhost:8080`。

> 当 server 配置了 `BASTION_SERVER_PUBLIC_KEY` 时，agent 注册成功后会自动把该公钥写入
> `~/.ssh/authorized_keys`（可通过 `bastion.agent.ssh-authorized-keys-file` 覆盖路径）。

### 5) 查看服务发现

```bash
curl http://127.0.0.1:8080/api/v1/agents
```

### 6) 一键连接（脚本，交互式）

```bash
bash bastion-server/scripts/one-click-connect.sh
```

默认行为：

- `server-url` 默认本机 `http://127.0.0.1:8080`
- 自动拉取在线 agent 列表并让你按编号选择
- 默认使用当前系统用户（可通过 `--user` 覆盖）
- server 生成的连接命令默认使用 `mosh`（可在配置中切换为 `ssh`）

常用参数示例：

```bash
# 指定用户
bash bastion-server/scripts/one-click-connect.sh --user root

# 跳过交互，直接指定 agent
bash bastion-server/scripts/one-click-connect.sh --agent <agentId> --user root

# 指定 server
bash bastion-server/scripts/one-click-connect.sh --server-url http://<server-ip>:8080 --user root
```

> 注意：默认命令为 `mosh user@agent-ip --ssh='ssh -p ssh-port'`。若目标环境未安装 `mosh`，可将 `bastion.connection.default-mode` 配置为 `ssh`。

## Agent 一键安装（systemd）

在目标跳板机执行（替换 `<server-ip>` 和公钥内容）：

```bash
curl -fsSL https://raw.githubusercontent.com/i-zrhe2016/bastion-platform/main/bastion-agent/scripts/install-agent.sh | \
  sudo bash -s -- \
    --server-url http://<server-ip>:8080 \
    --server-public-key "$(cat ~/.ssh/id_ed25519.pub)" \
    --tag env=prod \
    --tag role=jump
```

脚本会自动下载最新预编译二进制，无需安装 Rust。

安装脚本会：

- 复制二进制到 `/opt/bastion-agent/bastion-agent`
- 生成 `/opt/bastion-agent/application.yml`
- 写入并启动 `systemd` 服务 `bastion-agent`

## API 示例

### 注册

```bash
curl -X POST http://127.0.0.1:8080/api/v1/agents/register \
  -H 'Content-Type: application/json' \
  -d '{
    "agentId":"agent-001",
    "hostname":"jump-01",
    "ip":"10.0.0.11",
    "sshPort":22,
    "tags":{"env":"prod"}
  }'
```

### 一键连接

```bash
curl -X POST http://127.0.0.1:8080/api/v1/connections/one-click \
  -H 'Content-Type: application/json' \
  -d '{"agentId":"agent-001","username":"root"}'
```

返回包含：

- `token`
- `expiresAt`
- `connectCommand`（可直接执行）

## 密钥下发配置

`bastion-server` 可通过配置项把 SSH 公钥下发给 agent 注册响应：

```yaml
bastion:
  connection:
    server-public-key: ${BASTION_SERVER_PUBLIC_KEY:}
```

建议把 server 的公钥内容放入环境变量 `BASTION_SERVER_PUBLIC_KEY`，私钥保留在 server 本机。

## 生产建议（下一步）

- 将 registry 从内存迁移到 Redis/MySQL
- token 改为 JWT + 签名校验 + 单次消费
- SSH 连接走统一网关代理并审计（命令录像、会话回放）
- 对 agent 接口增加双向 TLS / mTLS 与签名认证

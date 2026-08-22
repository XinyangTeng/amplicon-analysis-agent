# Web、邀请制账户与可安装 App

从 `0.5.0` 起，Web 入口分为两个表面：

- `/`：公开介绍页，可被搜索引擎收录；
- `/app`：邀请制分析工作台，未登录时跳转到 `/login`。

统计分析仍复用 MCP 背后的 `AgentService` 与 R 函数，不在浏览器中复制计算逻辑。

```text
公开介绍页
  → 邀请码注册 / 登录
  → 用户独立工作区
  → 用户指定分组列并检查
  → 可选的右侧 AI 对话与 metadata 修正预览
  → 实验设计与计划
  → 一次性审批
  → Redis + Celery 队列
  → 受限 R 执行
  → 校验、报告与可选模型解读
```

## 推荐启动方式

复制环境变量模板，至少设置一个首次邀请码：

```powershell
Copy-Item .env.example .env
```

在 `.env` 中填写：

```dotenv
WEB_PORT=8001
AMPLICON_BOOTSTRAP_INVITE=请替换为至少12位的高强度邀请码
PRIVACY_CONTACT=你的联系邮箱
```

启动 Web、Redis、分析 Worker 和自动清理服务：

```powershell
.\scripts\start_stack.ps1
```

脚本会自动选择当前机器可用的 `docker compose` 或 `docker-compose`。
如果希望后台运行，使用 `.\scripts\start_stack.ps1 -Detach`。

中国网络环境下，Docker 构建默认使用阿里云 Ubuntu/PyPI 镜像和清华
CRAN 镜像，并对 APT、R 和 Python 下载自动重试。可以在 `.env` 中通过
`UBUNTU_MIRROR`、`CRAN_MIRROR`、`BIOCONDUCTOR_MIRROR` 和
`PIP_INDEX_URL` 单独替换。Bioconductor 默认使用官方镜像列表中的 Posit
节点，以兼顾历史版本兼容性和中国网络下的下载稳定性。

打开 `http://127.0.0.1:8001`。同一台电脑上的其他项目仍可继续使用 `127.0.0.1:8000`。

## 页面开发热映射

需要频繁修改 `src/amplicon_agent/web_static/` 下的 HTML、CSS 或 JavaScript 时，
使用开发覆盖配置把本地静态目录只读挂载进 Web 容器。第一次启用需要重建一次，
让镜像识别 `AMPLICON_STATIC_DIR`：

```powershell
.\scripts\start_frontend_dev.ps1 -Build
```

此后保存页面文件后直接刷新浏览器即可，不需要再次重建或重启容器：

```powershell
.\scripts\start_frontend_dev.ps1
```

如果浏览器在五分钟内仍显示旧的 CSS/JavaScript，使用 `Ctrl + Shift + R`
强制刷新。准备正式发布时仍应使用普通生产配置重新构建：

```powershell
docker-compose up -d --build
```

首次用户注册后，建议从 `.env` 删除 `AMPLICON_BOOTSTRAP_INVITE`，以后按需单独生成邀请码：

```powershell
docker-compose exec amplicon-web python scripts/manage_access.py `
  --workspace /workspace create-invite --uses 1 --days 14 --label internal-test
```

如果镜像中未包含 `scripts/`，也可以在已经安装项目依赖的本机执行：

```powershell
$env:PYTHONPATH="src"
python scripts/manage_access.py --workspace ".\workspace" `
  create-invite --uses 1 --days 14 --label internal-test
```

列出或撤销邀请码：

```powershell
$env:PYTHONPATH="src"
python scripts/manage_access.py --workspace ".\workspace" list-invites
python scripts/manage_access.py --workspace ".\workspace" revoke-invite <invite-id>
```

## 本机单进程开发模式

没有 Redis 时可以临时使用：

```powershell
.\scripts\start_web.ps1 -Port 8001 -SingleProcess `
  -BootstrapInvite "replace-with-a-long-test-code"
```

该模式只用于界面和功能开发。任务会在 Web 进程内执行，不能提供生产级 CPU、内存和并发隔离。

## 账户与数据隔离

- 邀请码仅保存 SHA-256 哈希，可设置有效期和使用次数；
- 密码使用带随机盐的 `scrypt` 哈希；
- 登录采用 `HttpOnly`、`SameSite=Lax` Cookie；
- 所有写请求需要当前会话的 CSRF 校验；
- 用户目录固定为 `workspace/users/<user-id>/`；
- 上传、计划和报告接口同时检查当前用户的资源归属；
- SQLite 只保存账户、会话、归属、任务状态和额度，不保存模型 API Key。

正式 HTTPS 部署必须设置：

```dotenv
AMPLICON_COOKIE_SECURE=true
```

## 任务队列与资源限制

Docker Compose 中包含：

- `redis`：消息与任务结果；
- `amplicon-web`：网页、账户和轻量文件检查；
- `amplicon-worker`：单并发 R 分析；
- `amplicon-cleanup`：每小时清理过期上传、计划、结果和会话。

默认限制：

| 项目 | 默认值 | 配置 |
|---|---:|---|
| 单文件上传 | 200 MB | `AMPLICON_MAX_UPLOAD_MB` |
| 单次总上传 | 500 MB | `AMPLICON_MAX_TOTAL_UPLOAD_MB` |
| 每用户存储 | 2048 MB | `AMPLICON_MAX_USER_STORAGE_MB` |
| 每用户活动任务 | 1 | `AMPLICON_MAX_ACTIVE_JOBS` |
| 分析总时长 | 3600 秒 | `AMPLICON_ANALYSIS_TIMEOUT_SECONDS` |
| 单个 R 子进程 | 1800 秒 | `AMPLICON_R_TIMEOUT_SECONDS` |
| Worker CPU | 2 核 | `docker-compose.yml` |
| Worker 内存 | 6 GB | `docker-compose.yml` |
| 数据保留 | 7 天 | `AMPLICON_RETENTION_DAYS` |

Linux Worker 还会对 R 子进程设置地址空间、CPU 时间和打开文件数限制。Windows 本机进程无法提供同等级边界，因此对外测试应使用 Docker 或云端容器。

## 模型额度与自带密钥

统计分析和固定报告不依赖模型。模型用于用户主动发起的数据问题对话、metadata 修正建议、连接测试和结果解读。

- 共享模型：运营者通过环境变量配置，实际费用与供应商额度扣在运营者配置的 `MODEL_API_KEY` 所属账户，默认每用户每月 10 次；
- 自带密钥（BYOK）：用户在网页填写，密钥只存在当前浏览器会话和本次 HTTP 请求中，不写入数据库、日志或报告；
- BYOK 调用不占共享额度；
- 共享调用只有成功后才计入月度用量；失败调用会释放额度；
- 每次成功的 AI 对话、结果解读或连接测试各计 1 次；
- 共享额度用完后，用户仍可使用自己的密钥；
- 自定义模型地址默认必须是 HTTPS；生产部署建议通过 `MODEL_ALLOWED_HOSTS` 设置域名白名单。

数据检查阶段的模型上下文只包含 metadata 的列名、取值概况、检查信息和有限代表行，不包含完整丰度矩阵。默认最多发送 40 个代表行、15 列，优先保留用户指定的分组、批次和梯度列；可通过 `AI_METADATA_MAX_ROWS` 和 `AI_METADATA_MAX_COLUMNS` 调小。模型只能生成修正预览；用户确认后系统生成新副本、保留原文件并再次执行确定性检查。

服务端共享模型：

```dotenv
MODEL_PROVIDER=qwen
MODEL_PROTOCOL=openai
MODEL_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
MODEL_NAME=qwen-plus
MODEL_API_KEY=你的服务端密钥
AMPLICON_MONTHLY_MODEL_QUOTA=10
MODEL_ALLOWED_HOSTS=dashscope.aliyuncs.com
```

## 删除与隐私

工作台“我的账户”提供：

- `DELETE MY DATA`：清除上传、计划、结果和模型调用记录，保留账户；
- `DELETE MY ACCOUNT`：注销账户并清除全部数据。

删除时会请求取消排队或运行中的任务。任务本身也会在开始和结束时检查取消状态。

公开隐私政策位于 `/privacy`。正式上线前必须：

- 填写实际运营主体和有效联系邮箱；
- 根据实际模型提供商补充第三方数据处理说明；
- 由熟悉中国数据与互联网服务合规的人员审阅；
- 不上传含直接身份标识、医疗隐私或无权处理的数据。

## 搜索引擎

只有介绍页和隐私政策允许收录。登录页、工作台、API 和报告均返回 `noindex`。

购买域名并部署后设置：

```dotenv
PUBLIC_BASE_URL=https://你的域名
```

服务会据此生成 canonical、`robots.txt` 和 `sitemap.xml`。面向中国大陆正式部署的准备清单见 [`DEPLOYMENT_CN.md`](DEPLOYMENT_CN.md)。

## 主要 Web API

- `POST /api/auth/register`、`POST /api/auth/login`、`POST /api/auth/logout`；
- `GET /api/auth/me`；
- `DELETE /api/me/data`、`DELETE /api/me/account`；
- `POST /api/uploads/inspect`；
- `POST /api/uploads/{id}/reinspect`；
- `POST /api/assistant/chat`；
- `POST /api/uploads/{id}/metadata/apply`；
- `GET /api/uploads/{id}/metadata/corrected`；
- `POST /api/plans`、`GET /api/plans`；
- `POST /api/plans/{id}/approve`；
- `POST /api/plans/{id}/run`；
- `GET /api/plans/{id}`、`GET /api/plans/{id}/validation`；
- `POST /api/plans/{id}/interpret`；
- `GET /api/plans/{id}/report`；
- `GET /api/model`、`POST /api/model/test`。

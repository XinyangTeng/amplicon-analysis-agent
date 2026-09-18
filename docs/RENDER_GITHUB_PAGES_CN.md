# GitHub Pages + Render 临时公网部署

## 架构

```text
访客
  ├─ GitHub Pages：公开介绍页、搜索入口
  └─ Render：登录、上传、API、R 分析、报告下载
       ├─ 同一个 Web 实例：FastAPI + Celery Worker + Celery Beat
       ├─ Render Key Value：任务队列与状态
       └─ Persistent Disk：用户上传、SQLite、运行结果和报告
```

GitHub Pages 只能托管静态文件，不能执行 Python、R、Redis 或 Celery。分析入口必须跳转到 Render，不能仅靠 GitHub Pages 完成分析。

## 为什么将 Web 与 Worker 放在同一个 Render 服务

项目当前以文件作为三表、计划、结果和报告的主要载体。Render 的持久磁盘只能挂载给一个服务，不能同时共享给独立 Web 与 Worker。`scripts/start_render.sh` 因此在同一实例内启动 Web、一个 Worker 和定时清理进程，三者共同读写 `/workspace`。

这是内测期部署方式。用户数上升后，应把文件迁移到对象存储、账户迁移到 PostgreSQL，再把 Web 和 Worker 独立扩缩容。

## 费用与规格提醒

- 完整分析曾按 Worker 约 6 GB 内存设计，`render.yaml` 默认选择 8 GB 的 `pro plus` Web 实例。
- 持久磁盘和后台计算属于付费能力；创建 Blueprint 前必须在 Render 页面确认实时价格。
- 免费 Web 只有 512 MB，空闲后会休眠，本地文件也会丢失，不适合运行本项目的全套 R 分析。
- 默认区域为新加坡。中国大陆访问速度仍取决于跨境网络，不等同于中国大陆备案服务器。

## 第一步：部署 Render

1. 确认代码已经推送到 GitHub。
2. 登录 Render，选择 **New → Blueprint**。
3. 连接 `XinyangTeng/amplicon-analysis-agent`，让 Render 读取仓库根目录的 `render.yaml`。
4. 创建前核对实例、Key Value 和 10 GB 磁盘的价格。
5. 填写 Render 要求的保密变量：
   - `AMPLICON_BOOTSTRAP_INVITE`：首次内测邀请码；
   - `PRIVACY_CONTACT`：隐私与删除请求联系方式；
   - 模型配置可暂时留空，或填写 `MODEL_PROVIDER`、`MODEL_PROTOCOL`、`MODEL_BASE_URL`、`MODEL_NAME`、`MODEL_API_KEY`、`MODEL_ALLOWED_HOSTS`。
6. 部署完成后记录地址，例如 `https://amplicon-analysis-agent.onrender.com`。
7. 打开 `/api/health`，确认返回健康状态；再使用邀请码完成一次小数据闭环。

不要把邀请码、模型 API Key 或 GitHub Token 写入 `.env` 后提交。

## 第二步：发布 GitHub Pages

1. 在 GitHub 仓库打开 **Settings → Pages**。
2. 将 Source 选择为 **GitHub Actions**。
3. 打开 **Settings → Secrets and variables → Actions → Variables**。
4. 新建仓库变量：
   - Name：`RENDER_APP_URL`
   - Value：Render 地址，末尾不要加 `/`。
5. 打开 **Actions → 发布 GitHub Pages 介绍页 → Run workflow**。
6. 发布后访问：`https://xinyangteng.github.io/amplicon-analysis-agent/`。

以后修改介绍页并推送后，GitHub Pages 会自动更新。修改后端并推送后，Render 会自动重新构建和部署。

## 本地开发与线上同步

本地仍使用 Docker Compose：

```powershell
Set-Location "E:\桌面\生信agent\amplicon-analysis-agent"
docker-compose up -d --build
```

本地修改完成并通过测试后：

```powershell
git add .
git commit -m "描述本次修改"
git push
```

GitHub 是代码中转站；GitHub Pages 和 Render 分别从同一仓库自动更新。线上上传的数据不会提交回 GitHub，而是保存在 Render 的持久磁盘中。

## 上线前最小验收

- Pages 首页的三个入口都指向 Render，而不是 `127.0.0.1`。
- Render `/api/health` 正常。
- HTTPS 下可以注册、登录，Cookie 不报错。
- 上传三表后刷新页面，任务仍存在。
- 运行期间关闭浏览器，再打开仍可查询任务状态。
- 结果报告和压缩包可以下载。
- 用户删除数据后，磁盘中的对应资源消失。
- Render 重启后，账户、任务和结果仍存在。

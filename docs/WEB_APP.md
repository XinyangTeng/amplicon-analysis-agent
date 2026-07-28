# Web 与可安装 App

项目从 `0.3.0` 起提供 FastAPI Web 服务和 PWA 前端。PWA 与浏览器页面使用同一个后端，不复制分析逻辑：

```text
Web/PWA
  → 上传缓存与输入检查
  → 实验设计确认
  → 分析合同与一次性审批
  → 原有 Python 服务层
  → 固定 R 函数
  → 自动校验与 HTML 报告
  → 可选模型解读
```

## 本地启动

Windows PowerShell：

```powershell
.\scripts\start_web.ps1
```

或手动运行：

```powershell
python -m pip install ".[web]"
$env:AMPLICON_WORKSPACE=(Join-Path (Get-Location) "workspace")
amplicon-web
```

打开 `http://127.0.0.1:8000`。在 Chrome 或 Edge 地址栏右侧选择“安装”，也可以点击页面左侧出现的“安装为 App”。安装后可作为独立窗口运行，分析仍由本机或服务器后端完成。

## Docker 启动

```powershell
Copy-Item .env.example .env
docker compose up --build
```

数据、计划、运行结果和模型配置保存到仓库的 `workspace/`，容器删除后仍保留。

## 模型接口

模型不是统计计算的必要条件。未配置模型时，文件检查、计划、审批、R 分析、校验和固定 HTML 报告均可使用；只有“使用当前模型解读结果”按钮不可用。

配置优先级：

1. `MODEL_*` 环境变量；
2. 当前服务进程中由设置页提交的 API Key；
3. `workspace/.amplicon-agent/model_config.json`；
4. 内置预设。

支持两种协议：

- `openai`：OpenAI Chat Completions 兼容接口，适用于 OpenAI、DeepSeek、通义千问兼容模式、本地兼容网关等；
- `anthropic`：Anthropic Messages 接口。

常用环境变量：

```text
MODEL_PROVIDER=openai_compatible | deepseek | qwen | anthropic | custom
MODEL_PROTOCOL=openai | anthropic
MODEL_BASE_URL=https://...
MODEL_NAME=模型名称
MODEL_API_KEY=密钥
MODEL_TIMEOUT_SECONDS=180
```

页面中的 API Key 是只写字段，后端不会把密钥返回给浏览器。设置页提供两种方式：

- 不勾选保存：只在当前服务器进程内存中使用，重启失效；
- 勾选保存：写入工作区私有配置文件，适合个人电脑，不建议公共服务器使用。

公共服务器推荐只通过 `MODEL_API_KEY` 环境变量注入。

## 公开测试的最低安全要求

- 设置长度足够的 `AMPLICON_WEB_TOKEN`，访问者在页面右上角输入；
- 使用 HTTPS 反向代理，不直接暴露开发服务器；
- 为每个测试环境使用独立 `workspace/`；
- 限制上传大小，并定期清理 `workspace/uploads/` 和 `workspace/runs/`；
- 不把 `.env`、模型密钥或真实受试者信息提交到 Git；
- 当前版本是单机测试版，不提供用户账号、配额、任务队列和多租户隔离。面向不受信任公众开放前，应再增加登录、任务队列、资源限制和对象存储。

## Web API

主要接口：

- `POST /api/uploads/inspect`：上传并检查三表，可附加树和代表序列；
- `POST /api/plans`：基于已检查上传生成分析合同；
- `POST /api/plans/{id}/approve`：一次性人工审批；
- `POST /api/plans/{id}/run`：后台运行；
- `GET /api/plans/{id}`：状态；
- `GET /api/plans/{id}/validation`：自动校验；
- `POST /api/plans/{id}/interpret`：调用当前模型并重建报告；
- `GET /api/plans/{id}/report`：HTML 报告；
- `GET/PUT /api/model`、`POST /api/model/test`：模型设置与连通测试。

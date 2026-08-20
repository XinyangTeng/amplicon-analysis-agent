# 面向中国用户的公开部署准备

当前代码已经具备公开介绍页和邀请制分析入口，但“代码可部署”不等于“可以直接对陌生用户开放”。建议分两阶段。

## 阶段一：无域名内测

- 使用 Docker Compose 在本机或校内服务器启动；
- 只向少量受邀测试者开放；
- 使用高强度、单次或短期邀请码；
- 不收集真实姓名，不上传个人敏感信息；
- 保持默认 7 天自动删除；
- 共享模型额度设为较小数值，优先鼓励 BYOK；
- 定期查看磁盘、Worker 内存、失败任务和 Redis 状态。

无域名时可以通过服务器 IP 测试，但不适合搜索引擎收录、HTTPS Cookie 和长期品牌传播。

## 阶段二：中国大陆正式公开

1. 确定实际运营主体。团队、课题组、学院或个人由谁承担账户、数据、服务器和投诉处理责任，需要先写清楚。
2. 购买域名和中国大陆云服务器。域名实名信息应与备案主体保持一致。
3. 通过云服务商提交 ICP 备案。工信部现行规则要求在境内提供非经营性互联网信息服务依法备案，网站首页按要求展示备案号并链接备案系统。
4. 按当地要求完成公安联网备案。相关规定要求符合条件的联网单位在正式联网后办理安全备案。
5. 配置 HTTPS、反向代理和域名，将 `AMPLICON_COOKIE_SECURE` 改为 `true`。
6. 配置 `PUBLIC_BASE_URL`、`PRIVACY_CONTACT`、真实运营主体、ICP备案号和公安备案号。
7. 只允许公开介绍页被搜索；分析入口、API 和结果报告保持 `noindex`。
8. 根据实际数据类型和第三方模型服务完成隐私政策、用户协议和个人信息处理清单的法律审阅。
9. 做备份恢复、漏洞更新、异常告警、日志脱敏和数据删除演练。

## 推荐拓扑

```text
域名 / HTTPS
    |
Nginx 或 Caddy
    |
FastAPI Web  ─── SQLite 账户与归属
    |
Redis
    |
Celery Worker ─── 每用户独立目录 ─── R 分析
    |
Celery Beat ─── 到期自动删除
```

单台服务器内测可以使用 SQLite。并发用户明显增加后，再把账户和任务元数据迁移到 PostgreSQL，并把大文件迁移到对象存储；不要把多台 Web 实例直接连接到同一个网络文件系统上的 SQLite。

## 上线必须填写的环境变量

```dotenv
PUBLIC_BASE_URL=https://example.cn
PRIVACY_CONTACT=privacy@example.cn
AMPLICON_COOKIE_SECURE=true
AMPLICON_RETENTION_DAYS=7
AMPLICON_MONTHLY_MODEL_QUOTA=10
MODEL_ALLOWED_HOSTS=dashscope.aliyuncs.com,api.deepseek.com
```

## 官方依据与办理入口

- 工业和信息化部：《非经营性互联网信息服务备案管理办法》

  https://www.miit.gov.cn/gyhxxhb/jgsj/cyzcyfgs/bmgz/xxtxl/art/2024/art_84a0cfa0ebd049bbbe751dca9a008e56.html

- 工业和信息化部备案管理系统

  https://beian.miit.gov.cn/

- 全国人大：《中华人民共和国个人信息保护法》

  https://www.npc.gov.cn/npc/c2/c30834/202108/t20210820_313088.html

- 中央网信办：《计算机信息网络国际联网安全保护管理办法》

  https://www.cac.gov.cn/2014-10/08/c_1112737294.htm

本清单是工程准备说明，不替代针对实际运营主体、数据内容和商业模式的法律意见。

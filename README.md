# 吕明远 - 项目作品集

> Java 后端开发 | Spring Boot + Vue3 + Python | 纺织行业数字化

---

## 关于我

颐鑫纺织 PMC 排程负责人，负责国内 PMC 与海外工厂（柬埔寨）生产管理系统开发与落地。具备独立主导企业级项目从 0 到 1 完整研发经验，涵盖业务调研、架构设计、前后端开发、AI 集成。

- 📧 网易邮箱：l19954462820@163.com
- 📧 Gmail：ql u62037@gmail.com
- 💻 GitHub：https://github.com/Kyle-lmy
- 📱 手机：19954462820

---

## 项目列表

### 🟦 纺织 ERP 智能管理系统

**时间**：2025.10 – 至今  
**角色**：主导开发（架构设计 / 后端 / 前端 / AI 服务全链路）

独立负责系统架构设计与全链路开发，已在柬埔寨工厂实际部署运行。

**技术栈**：Spring Boot 3.2 · Spring Security 6 · MyBatis-Plus 3.5 · MySQL 8 · Redis 7 · RabbitMQ · FastAPI · scikit-learn · Vue3 · Flyway · MinIO · Nginx

**核心亮点**

- 采用"模块化单体 + AI 微服务"架构，RabbitMQ 事件驱动解耦
- 打通下单→参数→打板→确样→采购→排产→出库完整链路，基于订单状态机设计 15 条自动化规则
- 构建客户评分、供应商评分、产线能力分析三大 AI Agent，集成 Qwen/DeepSeek API 实现自然语言 SQL 查询，Resilience4j 熔断降级
- JWT 双令牌机制（Access 30 分钟 + Refresh 7 天 + Redis 黑名单），防暴力破解
- 排产引擎基于贪心+约束满足算法，100+ 订单、10+ 产线秒级出结果，生成甘特图数据
- 19 个业务模块，覆盖纺织生产核心场景

📄 [查看完整开发文档](docs/纺织ERP-AI开发文档.md)

---

### 🟢 多部门生产进度跟踪工具

**时间**：2026.04 – 2026.06  
**角色**：PMC 负责人兼开发者

解决各部门生产进度信息孤岛问题，赴柬埔寨工厂出差一个月完成系统海外落地部署。

**技术栈**：Python 3 · tkinter · SQLite（WAL）· matplotlib · openpyxl · PyInstaller

**核心亮点**

- Python + SQLite（WAL 模式）+ tkinter GUI，.exe 打包放共享文件夹，零服务器成本
- 5 台电脑同时读写，SQLite WAL + busy_timeout 5秒 + 自动重试 3 次，无服务器场景下实现多端协同
- 同时跟踪 70–80 款在产订单，每款 10–40 个 SKU，总 SKU 达 700–3200 条
- matplotlib 内嵌 6 种图表（单款走势、各款完成率、甘特图等），支持导出 PNG / Excel
- 程序启动自动检查备份，每周增量备份到共享目录，保留最近 8 周

📄 [查看完整开发文档](docs/生产进度跟踪工具-开发文档.md)

---

## 技能清单

**Java 核心技术**：Java SE、Spring Boot 3.x、Spring Security、MyBatis-Plus、JVM（了解）、JUC（熟悉）

**数据库与持久层**：MySQL（索引优化、执行计划分析、事务隔离级别）、Redis（分布式锁、缓存设计）、Flyway 版本管理

**Java Web 生态**：Servlet 容器（Tomcat）、Spring 框架设计思想、分布式系统基础（RPC、分布式事务概念）

**AI 与自动化**：scikit-learn、FastAPI、Qwen/DeepSeek API 对接、Playwright、openpyxl

**前端**：Vue3、Element Plus、Pinia

**工具**：Git、Maven、Nginx、RabbitMQ、MinIO、Jenkins（基础）

---

## 简历

📄 [下载简历](resume/吕明远的简历.pdf)

---

## 项目经历（简述）

| 时间 | 项目 | 角色 |
|------|------|------|
| 2025.10 – 至今 | 纺织 ERP 智能管理系统 | 主导开发 |
| 2026.04 – 2026.06 | 生产进度跟踪工具 | 独立开发 |
| 2023.07 – 2025.03 | 公司物流后台管理系统 | 后端开发 |
| 2023.07 – 2025.03 | 无人机考试小程序后台 | 后端开发 |
| 2023.04 – 2023.06 | 医疗后台管理系统 | 后端开发 |

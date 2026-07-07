[纺织ERP-AI开发文档.md](https://github.com/user-attachments/files/29734142/ERP-AI.md)
# 纺织ERP智能管理系统 — 开发文档

> 版本：v1.5 | 日期：2026-07-07 | 作者：吕明远
> 项目代号：TexERP-AI
> v1.5 更新：文档评审后修订——修复Token存储矛盾、角色存储冗余、AI服务读写权限、Java版本不符；新增并发控制、软删除、全局异常处理、缓存策略、日志规范、性能SLA、接口幂等性、种子数据设计、柬埔寨部署考量；评分表改追加式写入、QC schema扩展、Redis Stream替代RabbitMQ、AI服务间认证
> v1.4 更新：合并 JWT 登录认证详细设计文档
> v1.3 更新：技术评审后修正——补全认证方案(JWT)、数据库迁移(Flyway)、支付记录表、批次追溯关联表、AI降级方案、文件API、排产日历、测试策略、批量操作API、路线图调整为16周

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [技术选型](#3-技术选型)
   - 3.1 后端
   - 3.2 AI 服务
   - 3.3 前端
   - 3.4 认证与授权方案 【v1.3】
   - 3.5 数据库迁移方案 【v1.3】
   - 3.6 测试策略 【v1.3】
   - 3.7 全局异常处理 【v1.5】
   - 3.8 缓存策略 【v1.5】
   - 3.9 日志规范 【v1.5】
   - 3.10 性能需求与 SLA 【v1.5】
   - 3.11 接口幂等性 【v1.5】
   - 3.12 种子数据设计 【v1.5】
4. [功能模块设计](#4-功能模块设计)
   - 4.1 订单管理
   - 4.2 采购管理
   - 4.3 仓库管理
   - 4.4 排产管理
   - 4.5 系统管理
   - 4.6 BOM与配方管理 【新增】
   - 4.7 成本核算管理 【新增】
   - 4.8 外发加工管理 【新增】
   - 4.9 QC标准管理 【新增】
   - 4.10 工作台与仪表盘
   - 4.11 消息通知中心
   - 4.12 数据导入导出
   - 4.13 样品/确样管理 【v1.2 P0】
   - 4.14 色卡/Lab Dip 管理 【v1.2 P0】
   - 4.15 裁床管理 【v1.2 P0】
   - 4.16 计件工资 【v1.2 P1】
   - 4.17 批号/缸号追溯 【v1.2 P1】
   - 4.18 对账单管理 【v1.2 P1】
   - 4.19 司机绩效考核 【v1.2 P1】
5. [AI Agent 设计](#5-ai-agent-设计)
6. [自动化算法设计](#6-自动化算法设计)
   - 6.5 并发控制策略 【v1.5】
7. [数据库设计](#7-数据库设计)
8. [API 接口设计](#8-api-接口设计)
9. [开发路线图](#9-开发路线图)
10. [风险评估与对策](#10-风险评估与对策)
11. [部署方案](#11-部署方案) 【新增】
   - 11.5 柬埔寨部署考量 【v1.5】
12. [遗漏项自查记录](#12-遗漏项自查记录)

---

## 1. 项目概述

### 1.1 项目背景

传统纺织企业面临以下痛点：
- **信息孤岛**：订单、采购、库存、排产各环节数据不互通，全靠人工 Excel 传递
- **经验依赖**：客户信用评估、供应商质量判断、产线产能分配全靠老员工经验，人员流失即知识流失
- **重复劳动**：订单流转中大量"传话"工作（录参数→通知打板→催采购→追到货），占用 PMC 大量精力
- **决策滞后**：异常（交期延迟、质量异常、库存预警）靠人发现，往往是事后补救

### 1.2 项目目标

构建一套 **嵌入 AI Agent 的纺织 ERP 系统**，核心目标：

1. **全流程线上化**：下单→参数→打板→采购→入库→排产→出库，一条链路跑通
2. **AI 辅助决策**：Agent 自动分析客户质量、供应商可靠度、产线能力，给出量化评分
3. **规则驱动自动化**：符合条件时自动触发下一步（如：面料到位自动排产、交期临近自动预警）
4. **数据可追溯**：每个订单的全生命周期操作日志可查，责任到人

### 1.3 核心业务流程

```
客户下单  →  参数录入  →  打板确认  →  采购计划生成
                                             ↓
  出货发货  ←  质检入库  ←  生产排产  ←  到货入库
```

### 1.4 系统边界

| 范围 | 说明 |
|------|------|
| **包含** | 订单管理、参数/BOM管理、打板/确样跟踪、色卡/Lab Dip管理、裁床管理、采购管理、仓库管理、排产管理、计件工资、对账单、司机绩效、AI分析中心、系统管理 |
| **不包含** | 财务总账（只做业务对账，不做资产负债表）、HR考勤、设备物联网对接（预留接口） |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    前端 SPA (Vue 3)                          │
│              订单工作台 │ 采购面板 │ 排产看板 │ AI分析         │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS (WebSocket 可选，用于实时通知推送)
┌──────────────────────▼──────────────────────────────────────┐
│                   API Gateway (Nginx)                        │
└──────┬──────────────────────────────┬───────────────────────┘
       │                              │
┌──────▼──────────┐          ┌───────▼──────────────────────┐
│  Spring Boot    │          │  Python AI Service (FastAPI)  │
│  核心业务服务    │  ◄───►  │  Agent 推理 / 数据分析 / 评分  │
│                 │   REST   │                               │
│  · 订单管理     │          │  · 客户评分 Agent             │
│  · 采购管理     │          │  · 供应商评分 Agent            │
│  · 仓库管理     │          │  · 产线能力分析 Agent          │
│  · 排产引擎     │          │  · 异常预警 Agent              │
│  · 权限管理     │          │  · NLP查询接口                 │
└──────┬──────────┘          └──────────┬────────────────────┘
       │                                │
       │   Redis Stream 事件总线        │
       │   (事件驱动自动化)              │
       │                                │
┌──────▼────────────────────────────────▼────────────────────┐
│                      数据层                                  │
│        MySQL 8.0          Redis          MinIO (文件)        │
│     (业务数据主库)      (缓存/队列)     (图纸/质检报告)        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 为什么选"模块化单体 + AI 微服务"

| 决策 | 理由 |
|------|------|
| **单体而非微服务** | 团队 1 人开发，微服务运维成本远大于收益。模块化分包，清晰即可 |
| **AI 独立服务** | Python 生态的 LLM/数据分析库远强于 Java，独立部署不污染主服务 |
| **事件驱动** | 订单状态变更 → Redis Stream 事件 → 自动触发下游动作（通知采购、启动排产等）。v1.5 起用 Redis Stream 替代 RabbitMQ，单机部署无需额外服务 【v1.5更新】 |

### 2.3 模块划分

```
tex-erp/
├── tex-erp-common        # 公共类：异常、工具、常量
├── tex-erp-system        # 系统管理：用户、角色、权限、日志
├── tex-erp-order         # 订单管理：下单、参数、打板、确样、色卡/Lab Dip
├── tex-erp-procurement   # 采购管理：采购单、供应商、对账单
├── tex-erp-warehouse     # 仓库管理：入库、出库、库存、批号追溯
├── tex-erp-production    # 排产管理：产线、排程、工单、裁床、计件工资、司机绩效
├── tex-erp-ai-bridge     # AI 桥接：调用 Python 服务、缓存评分
├── tex-erp-event         # 事件处理：RabbitMQ 消费者，自动化编排
└── tex-erp-web           # 启动入口 + 配置
```

---

## 3. 技术选型

### 3.1 后端

| 技术 | 版本 | 用途 |
|------|------|------|
| Java | 21 LTS | 主力语言（编译目标 sourceCompatibility=17 保持兼容） |
| Spring Boot | 3.2.x | 应用框架 |
| Spring Security | 6.x | 权限控制（RBAC） |
| jjwt (jjwt-api / jjwt-impl / jjwt-jackson) | 0.11.5 | JWT 生成解析 |
| MyBatis-Plus | 3.5.x | ORM，代码生成 |
| MySQL | 8.0 | 业务数据库 |
| Redis | 7.x | 缓存 + 分布式锁 |
| Redis Stream | 7.x 内置 | 事件总线，异步自动化（v1.5 起替代 RabbitMQ，单机部署资源更省） 【v1.5更新】 |
| Flyway | 9.x | 数据库迁移版本管理 【v1.3新增】 |
| SpringDoc | 2.3+ | OpenAPI 文档自动生成 【v1.3新增】 |
| Resilience4j | 2.x | AI 服务熔断降级 【v1.3新增】 |
| JUnit 5 | 5.10+ | 单元测试 【v1.3新增】 |
| TestContainers | 1.19+ | 集成测试（MySQL容器） 【v1.3新增】 |
| MinIO | 最新稳定版 | 文件存储（图纸、质检照片） |
| Nginx | 1.24 | 反向代理，前端静态资源 |

### 3.2 AI 服务

| 技术 | 版本 | 用途 |
|------|------|------|
| Python | 3.12 | AI 服务语言 |
| FastAPI | 0.110+ | AI API 框架 |
| SQLAlchemy | 2.0 | 双连接：只读连接查业务数据 + 读写连接写评分表 【v1.5修正】 |
| scikit-learn | 1.4 | 评分模型、趋势预测 |
| openai / httpx | - | 对接 LLM（Qwen / DeepSeek） |
| pandas / numpy | - | 数据分析 |

### 3.3 前端

| 技术 | 版本 | 用途 |
|------|------|------|
| Vue | 3.4+ | 前端框架 |
| Element Plus | 2.5+ | UI 组件库 |
| Pinia | 2.1 | 状态管理 |
| ECharts | 5.5 | 数据分析图表 |
| Axios | 1.6 | HTTP 请求 |
| Vite | 5.x | 构建工具 |
| Playwright | 最新版 | E2E 测试（关键流程自动化测试） 【v1.5新增】 |
| Vitest | 1.x | 前端单元测试（工具函数） 【v1.5新增】 |

---

### 3.4 认证与授权方案 【v1.3 技术评审 P0-1】

> 阶段一第一天就要写登录。不定认证方案，第一个 Controller 都写不了。

#### 3.4.1 整体架构

```
┌──────────┐     ┌──────────────┐     ┌──────────┐
│  Vue3    │────▶│ Spring Boot  │────▶│  MySQL   │
│  前端    │     │  API 层      │     │  用户表  │
└──────────┘     └──────┬───────┘     └──────────┘
                        │
                 ┌──────┴───────┐
                 │    Redis     │
                 │ token黑名单  │
                 │ 登录失败计数  │
                 └──────────────┘
```

#### 3.4.2 JWT 双 Token 机制

| Token 类型 | 载体 | 有效期 | 存储位置 |
|-----------|------|--------|----------|
| Access Token | JWT (HS256) | 30 分钟 | Pinia（内存）+ sessionStorage（刷新不丢失） |
| Refresh Token | UUID | 7 天 | Redis（服务端）+ httpOnly Cookie（浏览器端，前端 JS 不可读） |

> **【v1.5修正】Token 存储方案统一说明**：
> - Access Token 不用 localStorage（XSS 风险），不用 httpOnly cookie（与 Bearer Token 方案冲突，前端 JS 无法读取设置 Header）
> - Pinia 内存存储保证安全性，sessionStorage 兜底保证页面刷新不丢失（关闭标签页自动清除）
> - Refresh Token 用 httpOnly Cookie 传输，后端从 Cookie 提取，前端 JS 无法读取，防 XSS 盗取

**登录流程：**

1. 前端发送 `POST /api/auth/login`，body 为 `{ username, password }`
2. 后端通过 `AuthenticationManager` 调用 `UserDetailsService.loadUserByUsername()` 从数据库查询用户
3. 使用 `BCryptPasswordEncoder` 比对密码
4. 认证成功，生成 access_token 和 refresh_token
5. 返回 `{ accessToken, expiresIn }` 给前端（access_token 存 Pinia+sessionStorage）；同时通过 `Set-Cookie` 将 refresh_token 写入 httpOnly Cookie 【v1.5修正】

**请求认证流程：**

1. 前端每次请求在 Header 携带 `Authorization: Bearer <accessToken>`
2. `JwtAuthenticationFilter` 从 Header 提取 token
3. `JwtUtil.validateToken()` 验证 token 有效性（签名 + 过期 + 黑名单）
4. 验证通过，将用户信息设置到 `SecurityContextHolder`
5. 请求进入 Controller 层

**Token 刷新流程：**

1. 前端 Axios 响应拦截器捕获 401
2. 自动调 `POST /api/auth/refresh`，refresh_token 由浏览器自动从 httpOnly Cookie 携带（前端 JS 无需手动传） 【v1.5修正】
3. 后端从 Cookie 提取 refresh_token 验证，旧 refresh_token 立即失效
4. 返回新的 access_token；同时通过 `Set-Cookie` 写入新的 refresh_token（refresh_token 轮换）
5. 前端更新 Pinia/sessionStorage 中的 access_token，重试原请求
6. 刷新失败 → 清除前端 token，跳转登录页

#### 3.4.3 Token 设计细节

**Access Token：**
- 签发算法：HS256（HMAC-SHA256）
- Payload：userId、username、roles（角色列表）、exp（过期时间）、iat（签发时间）

**Refresh Token：**
- Payload：userId、username、jti（唯一标识）
- Redis 存储：`refresh:<userId>:<jti>`，值为签发时间
- 防重放：每次刷新后旧 refresh_token 立即从 Redis 删除，若检测到已失效 token 被使用，视为攻击，使该用户所有 token 失效

**密钥管理：**
- 使用 `application.yml` 中的配置项 `jwt.secret`
- 密钥长度至少 256 bits（32 字节，即 32 个 ASCII 字符） 【v1.5修正：消除"256位"歧义】
- 生产环境通过环境变量注入，禁止写入代码仓库

#### 3.4.4 核心类设计

| 类 | 职责 | 关键说明 |
|----|------|----------|
| **JwtUtil** | token 生成/解析/验证 | `generateAccessToken()` / `generateRefreshToken()` / `validateToken()` / `isTokenExpired()` |
| **JwtAuthenticationFilter** | 请求拦截，校验 token | 继承 `OncePerRequestFilter`，提取 Header Bearer Token，验证后设 SecurityContext |
| **UserDetailsServiceImpl** | 从 DB 加载用户 | 实现 `UserDetailsService`，查询用户表 + 关联角色表，返回 UserDetails |
| **SecurityConfig** | Spring Security 配置 | 禁用 CSRF、STATELESS Session、配置公开接口白名单、过滤器顺序、BCrypt 编码器 |

**SecurityConfig 关键配置：**
- 禁用 CSRF（前后端分离不需要）
- Session 策略：`SessionCreationPolicy.STATELESS`
- 公开接口：`/api/auth/login`、`/api/auth/register`、swagger 文档路径
- JwtAuthenticationFilter 放在 UsernamePasswordAuthenticationFilter 之前
- 密码编码器：BCryptPasswordEncoder（cost factor=12）
- 自定义 401/403 异常响应格式

#### 3.4.5 角色与权限

| 角色 | 权限范围 |
|------|----------|
| **admin** | 全功能 + 用户管理 + 系统配置 |
| **pmc** | 订单全流程、排产、客户/供应商查看、AI分析查看 |
| **procurement** | 采购管理、供应商管理、到货登记 |
| **warehouse** | 入库、出库、库存查询、质检登记 |
| **production** | 排产查看、生产报工、裁床、计件工资 |
| **viewer** | 所有模块只读（老板视角） |

权限粒度：菜单级（路由守卫）+ 按钮级（`v-if` 指令）。权限标识通过 `t_user_role` 关联表查询，一人多角色。 【v1.5修正：删除 t_user.roles 冗余字段，统一用关联表】

#### 3.4.6 安全策略

**密码安全：**
- BCrypt 加密存储，cost factor=12
- 密码长度 6-20 位，至少包含字母和数字
- 日志不记录明文密码

**防暴力破解：**
- Redis 记录 `login:fail:<username>`，值为失败次数
- 同一用户名 5 分钟内失败 5 次，锁定 15 分钟
- 锁定期间返回"账号已被临时锁定，请稍后重试"

**Token 黑名单：**
- 登出时 access_token 加入 Redis 黑名单
- Key: `token:blacklist:<jti>`，TTL = token 剩余有效期
- JwtAuthenticationFilter 每次请求检查黑名单

#### 3.4.7 前端对接规范

**Token 存储：** Access Token 存 Pinia（内存）+ sessionStorage（刷新不丢失）；Refresh Token 由后端写入 httpOnly Cookie，前端 JS 不可读。不用 localStorage（XSS 风险）。 【v1.5修正：统一存储方案】

**Axios 拦截器：**
- 请求拦截器：自动注入 `Authorization: Bearer <token>`
- 响应拦截器：捕获 401 → 调 `/api/auth/refresh` → 成功则重试原请求 → 失败则跳登录页

**Vue Router 路由守卫：** 检查 token 是否存在，无 token 且目标路由需认证 → 跳转登录页。

#### 3.4.8 异常处理规范

| 场景 | HTTP 状态码 | 响应 message |
|------|------------|-------------|
| 用户名或密码错误 | 401 | "用户名或密码错误" |
| Token 过期 | 401 | "登录已过期，请重新登录" |
| Token 无效 | 401 | "无效的认证凭证" |
| 账号被禁用 | 403 | "账号已被禁用" |
| 账号被锁定 | 423 | "账号已被临时锁定，请稍后重试" |
| 权限不足 | 403 | "权限不足，请联系管理员" |

统一响应格式：
```json
{
  "code": 401,
  "message": "用户名或密码错误",
  "data": null,
  "timestamp": 1718524800000
}
```

#### 3.4.9 JWT 配置项参考

```yaml
# application.yml
jwt:
  secret: ${JWT_SECRET}              # 环境变量注入，禁止提交到代码仓库
  access-token-expiration: 30m       # 30分钟（Duration 格式）
  refresh-token-expiration: 7d       # 7天（Duration 格式）

# 登录失败限制
login:
  max-fail-count: 5       # 最大失败次数
  fail-lock-minutes: 15   # 锁定时间（分钟）
  fail-time-window: 5     # 失败计数窗口（分钟）
```

#### 3.4.10 开发注意事项

1. **密钥安全**：`jwt.secret` 禁止提交到代码仓库，使用环境变量或私有配置文件
2. **HTTPS**：生产环境强制 HTTPS，防止 token 被中间人截获
3. **日志脱敏**：登录日志不记录明文密码
4. **SQL 注入**：MyBatis 用 `#{}` 而非 `${}`
5. **CORS**：配置允许的前端域名，不要用 `*`
6. **接口限流**：登录接口建议加限流（如每秒 3 次）
7. **Refresh Token 轮换**：每次刷新返回新的 refresh_token，旧 token 立即失效

---

### 3.5 数据库迁移方案 【v1.3 技术评审 P0-2】

> 20+ 张表，手动 ALTER TABLE = 迟早生产事故。

#### 工具选型：Flyway

```yaml
# Spring Boot 自动集成 (flyway-core 依赖即可)
命名规范:
  V1.0__init_schema.sql       # 初始建表
  V1.1__add_bom_tables.sql    # BOM 相关表
  V1.2__add_cutting.sql       # 裁床相关表
  V1.3__add_payment.sql       # 支付记录表

原则:
  - 每版本只追加字段/表，不修改现有结构（与你已有规则一致）
  - 每个 migration 配一个 undo SQL（Flyway undo 或手动维护）
  - migration 文件存 tex-erp-docs/sql/migrations/
```

---

### 3.6 测试策略 【v1.3 技术评审 P1-3】

> 19 个模块一人开发，不写测试 = 改一个崩三个。

```
后端:
  JUnit 5 + Mockito      → Service 层单元测试（订单状态机、排产算法必测）
  TestContainers          → Repository 集成测试（MySQL 容器，真实 SQL 验证）
  Spring Boot Test        → Controller 集成测试（MockMvc）

前端:
  Vitest                  → 工具函数（日期格式化、单位换算等）
  Playwright              → 关键流程 E2E（下单→参数→打板→采购 一条线）

覆盖率目标:
  核心业务 Service 层: 80%+（订单状态机、排产算法、采购自动生成）
  其他 Service: 60%+
  Repository: 关键查询 100%
  Controller: 正常/异常路径各一条
  前端: 不追求覆盖率，只测关键路径
```

---

### 3.7 全局异常处理 【v1.5 新增】

> `@RestControllerAdvice` 统一捕获，所有接口返回标准化错误响应。

| 异常类型 | HTTP 状态码 | 错误码 | 说明 |
|----------|------------|--------|------|
| BusinessException | 400 | TEX-{模块}-{序号} | 业务校验失败（如订单状态不允许此操作） |
| ValidationException | 400 | TEX-VAL-001 | 参数校验失败，返回字段级错误信息 |
| AuthenticationException | 401 | TEX-AUTH-001 | 认证失败（token 无效/过期） |
| AccessDeniedException | 403 | TEX-AUTH-002 | 权限不足 |
| OptimisticLockException | 409 | TEX-CONC-001 | 并发冲突（数据已被他人修改） |
| Exception | 500 | TEX-SYS-001 | 未预期异常，仅返回"系统繁忙，请稍后重试" |

**日志策略**：5xx 记 ERROR + 完整堆栈；4xx 记 WARN；业务校验记 INFO。

### 3.8 缓存策略 【v1.5 新增】

| 缓存对象 | TTL | 失效策略 | 说明 |
|----------|-----|----------|------|
| 数据字典（面料类型/颜色/枚举） | 永不过期 | 变更时主动刷新 | 读多写少 |
| 用户权限信息 | 30min | 角色变更时刷新 | 减少每次请求查 DB |
| 供应商/客户评分 | 1h | AI 重算后刷新 | 评分计算后缓存 |
| 排产结果 | 5min | 排产变更时清除 | 频繁变更，短缓存 |
| 库存数量 | 不缓存 | — | 强一致性要求，直接查 DB |
| 空值缓存 | 60s | — | 防缓存穿透 |

**缓存雪崩防护**：TTL 加随机偏移量（±60s），避免同时过期。

### 3.9 日志规范 【v1.5 新增】

```
日志格式：JSON 结构化（便于后续 ELK 采集）
日志级别：
  ERROR  系统异常、第三方调用失败、数据一致性风险
  WARN   业务异常、降级触发、接近阈值
  INFO   关键业务操作（订单状态变更、排产确认等）
  DEBUG  调试信息（生产默认关闭）

敏感信息脱敏：密码、token、手机号中间四位
日志保留：ERROR 90天，INFO 30天，DEBUG 7天
日志存储：本地文件 + 按天滚动（单机部署暂不上 ELK）
```

### 3.10 性能需求与 SLA 【v1.5 新增】

| 指标 | 目标 | 说明 |
|------|------|------|
| 列表查询（分页） | P95 < 500ms | 订单/采购/库存列表 |
| 详情查询（单条+关联） | P95 < 300ms | 订单详情含参数/打板/采购 |
| 排产算法（100订单×10产线） | < 3s | 贪心+约束算法 |
| AI 评分计算 | P95 < 5s | 含数据库查询+模型计算 |
| Excel 导入（1000行） | < 10s | 含校验+入库 |
| 并发支持 | 50 并发用户 | 工厂规模 |
| 数据量预估 | 3年 ~50万订单 | ~500万条明细行 |

### 3.11 接口幂等性 【v1.5 新增】

> 写操作支持客户端传递 `requestId`（UUID），防止网络重试导致重复数据。

```
方案：
  - 客户端每次写操作生成 requestId（UUID）
  - 服务端用 Redis 记录 requestId（TTL 10min）
  - 相同 requestId 的重复请求直接返回首次结果
  - 至少覆盖：创建订单、入库、出库、报工、收付款登记
```

### 3.12 种子数据设计 【v1.5 新增】

```
init.sql 包含以下种子数据：
├── 初始管理员账户（admin/admin123 BCrypt加密，首次登录强制改密）
├── 角色数据（admin/pmc/procurement/warehouse/production/viewer 6个角色）
├── 数据字典（面料类型、颜色、单位、QC检查项类型等枚举 INSERT）
├── 默认 QC 标准模板（通用标准一套）
├── 默认系统参数（损耗率默认值、安全库存系数、预警阈值等）
└── 产线日历初始化（当年工作日历，可批量生成，支持手动调整）
```

---

## 4. 功能模块设计

### 4.1 订单管理模块（下单 → 参数 → 打板）

#### 4.1.1 下单

```
输入：客户信息、面料品种、数量、交期、特殊要求
输出：订单号（规则：OD + 年月日 + 3位流水，如 OD260616001）

字段设计：
├── 基础信息：订单号、客户ID、客户名称、联系人、交期
├── 产品信息：面料编码、颜色、克重、门幅、数量（米/公斤）
├── 状态信息：状态(枚举)、优先级、备注
├── 审计信息：创建人、创建时间、更新时间
└── AI 标注：客户风险等级、历史合作评分（由Agent自动关联）
```

#### 4.1.2 参数管理

订单确认后，进入参数定义阶段：

- **面料参数**：纱支、密度、成分、克重、门幅、缩率
- **工艺参数**：染色方式、后整理要求、色牢度要求
- **包装参数**：匹长、卷装方式、标签要求
- **关联**：参数表关联订单号，支持参数模板复用（同类订单一键带入）

#### 4.1.3 打板管理

- 打板工单生成（自动从参数创建）
- 打板状态：待打板 → 打板中 → 已寄出 → 客户确认 / 需重打
- 打板记录：日期、板号、寄出日期、快递单号、客户反馈
- 自动化：客户N天未反馈 → Agent 提醒催办

### 4.2 采购管理模块

#### 4.2.1 采购需求自动生成

打板确认后，系统根据 BOM + 订单数量 + 损耗率，**自动计算采购需求**：

```
纱线需求量 = 订单数量(kg) × (1 + 损耗率) / 成品率
辅料需求量 = 订单数量 × 辅料系数

生成采购建议单（待人工确认），包含：
- 物料名称、规格、数量、建议供应商（按评分排序）
- 历史采购价、建议到货日期（按排产倒推）
```

#### 4.2.2 供应商管理

每个供应商维护档案：
- 基础信息：名称、联系人、账期、资质
- 评分维度（Agent 自动计算）：
  - **质量合格率** = 合格批次 / 总到货批次
  - **交期准时率** = 准时交货次数 / 总交货次数
  - **价格稳定性** = 近N次报价标准差 / 均价
  - **配合度评分** = 基于退换货响应速度、沟通效率
- 综合评分 = 加权求和，生成供应商排行榜

### 4.3 仓库管理模块

#### 4.3.1 到货入库

```
采购到货 → 质检 → 合格/不合格

合格：扫码入库 → 库存增加 → 触发"排产检查"
不合格：生成退货单 → 扣供应商质量分 → 触发重新采购
```

#### 4.3.2 出库

```
生产完成 → 质检 → 入库 → 按订单发货出库

支持：
- 整单出库、分批出库
- 出库单关联物流单号
- 出库后订单状态自动变更
```

#### 4.3.3 库存管理

- 实时库存查询
- 安全库存预警（低于阈值自动提醒）
- 库龄分析（超过N天的库存高亮）
- 呆滞料报表

### 4.4 排产管理模块

#### 4.4.1 排产核心逻辑

```
输入：
- 待排产订单列表（已确认、物料齐套）
- 产线列表（每条产线日产能、当前排期）
- 订单交期

排产引擎：
1. 按交期紧迫度排序
2. 按产线匹配度分配（某类面料优先给擅长的产线）
3. 按产能倒推开工日期
4. 冲突检测：超产能自动提示

输出：
- 每日生产计划（哪条线做什么订单、做多少）
- 甘特图可视化
- 预计完工日期 vs 要求交期对比
```

#### 4.4.2 排产自动化触发

| 触发事件 | 自动化动作 |
|----------|-----------|
| 打板确认 | 生成采购需求 |
| 物料全部到齐 | 自动排入生产队列 |
| 产线空闲 | 从待排池自动拉取最优订单 |
| 交期临近(距交期<3天未开工) | 高亮预警 + 推送通知 |

### 4.5 系统管理模块

- 用户管理 + RBAC 角色权限
- 操作日志（谁在什么时间做了什么）
- 数据字典（面料类型、颜色、供应商类别等枚举）
- 系统参数配置（损耗率默认值、预警阈值等）

### 4.6 BOM 与配方管理 【v1.1 新增】

> **为什么缺了不行**：订单→参数→采购的核心桥梁。没有 BOM，采购需求就是拍脑袋。

#### 4.6.1 BOM 结构

```
成品面料（订单产品）
  ├── 经纱：XX规格 × 用量(kg/m)
  ├── 纬纱：XX规格 × 用量(kg/m)
  ├── 染料：XX色号 × 用量(g/kg)
  ├── 助剂：XX类型 × 用量(g/L)
  └── 包装：纸管/塑料袋 × 数量(个/卷)
```

#### 4.6.2 BOM 版本管理

- 同一面料类型可有多版 BOM（如 v1.0 老配方、v2.0 优化配方）
- 打板阶段使用"打板版 BOM"，确认后转为"量产版 BOM"
- 版本变更记录：谁、何时、改了哪个物料、用量从X变Y
- 采购需求按「当前生效版本 BOM」自动计算

#### 4.6.3 BOM 与工序关联

```
BOM 行项 ──关联──► 工序（染色 / 织造 / 后整理）
  ├── 染色工序需要：染料 + 助剂 + 水电气预估
  ├── 织造工序需要：经纱 + 纬纱
  └── 后整工序需要：柔软剂 / 定型助剂
```

工序维度可支撑后续**工序级成本核算**和**产线负荷侧写**。

### 4.7 成本核算管理 【v1.1 新增】

> **为什么缺了不行**：客户评分里「利润贡献度」、供应商评分里「价格竞争力」，没有成本数据就是空转。

#### 4.7.1 成本构成

```
订单成本 = 原料成本 + 人工成本 + 制造费用 + 外发费用 + 损耗
        + 包装 + 物流 + 打板费摊销 + 管理费分摊
```

#### 4.7.2 成本采集方式

| 成本项 | 采集方式 | 数据来源 |
|--------|----------|----------|
| 原料成本 | 采购入库价 × BOM用量 | 采购单 + BOM |
| 人工成本 | 工价 × 产量 | 排产工单 + 工价配置 |
| 制造费用 | 按产线日费率分摊 | 产线日费率 × 生产天数 |
| 外发费用 | 外发加工结算价 | 外发单 |
| 损耗 | (原料成本 + 人工) × 损耗率 | 系统参数 |

#### 4.7.3 利润自动计算

```
订单毛利 = 订单金额 - 订单成本
毛利率   = 毛利 / 订单金额
```

此数据直接喂给客户评分 Agent 的"利润贡献度"维度，以及供应商评分 Agent 的"价格竞争力"维度（采购价 vs 历史均价）。

### 4.8 外发加工管理 【v1.1 新增】

> **为什么缺了不行**：排产产能超载时，"外发"是纺织厂最常见的补救手段。没有这个，排产引擎遇到瓶颈只能报错。

#### 4.8.1 外发场景

- 产能不足（排产检测到某产线 >120%）
- 特殊工艺本厂做不了（如特殊后整理）
- 急单插入导致原计划被打乱

#### 4.8.2 外发流程

```
识别外发需求 → 选择外发厂 → 发料出库 → 外发生产 → 回收质检 → 结算
```

#### 4.8.3 外发厂管理

- 类似供应商档案，维护外发厂能力（擅长品类、产能、品质良率）
- 外发评分维度：品质合格率、交期准时率、价格
- Agent 自动推荐：当排产检测到产能不足，推荐可外发厂

### 4.9 QC 标准管理 【v1.1 新增】

> **为什么缺了不行**：不同客户对面料的质量标准不一样（欧美客户色牢度要求高，内销客户对色差容忍度低）。没有 QC 标准模板，质检就是空跑。

#### 4.9.1 QC 标准模板

```yaml
QC标准模板:
  模板名称: "欧标A类-婴童面料"
  检查项目:
    - 色牢度(耐水): ≥4级
    - 色牢度(耐摩擦): ≥3-4级(干) / ≥3级(湿)
    - 色差(ΔE): ≤1.5
    - 门幅偏差: ±1.5cm
    - 克重偏差: ±3%
    - 匹长偏差: ±2%
    - 外观疵点: 每100m ≤5个
```

#### 4.9.2 关联关系

- 客户档案绑定默认 QC 标准（老客户自动带出）
- 订单创建时可覆盖（特殊批次加严标准）
- 质检登记时自动对号入座 — 检测值 vs 标准值 → 自动判「合格/不合格」

### 4.10 工作台与仪表盘 【v1.1 新增】

> **为什么缺了不行**：一登录就看到一堆菜单，不知道先干什么。每个角色需要自己的首页。

#### 4.10.1 角色化工作台

| 角色 | 首页内容 |
|------|----------|
| PMC/跟单 | 待处理订单数、交期预警列表、打板待确认、物料待到位 |
| 采购 | 待采购需求、供应商到货日历、质检不合格批次数 |
| 仓库 | 待入库清单、待出库清单、库存预警 |
| 生产 | 今日产线任务、产线负载率、品质良率趋势 |
| 老板/管理 | 订单交付率、产值统计、客户/供应商评分排行、毛利率趋势 |

#### 4.10.2 全局仪表盘指标

```
KPI 卡片: 当月订单数 / 当月产值 / 交期达成率 / 质量合格率
趋势图: 近6个月订单量 / 产值 / 毛利率 曲线
风险地图: 高风险客户 / 重点监控供应商 / 产能预警产线
```

### 4.11 消息通知中心 【v1.1 新增】

> **为什么缺了不行**：自动化做了但没人知道，等于没做。通知是自动化的最后一公里。

#### 4.11.1 通知类型

| 渠道 | 场景 | 优先级 |
|------|------|--------|
| 系统内通知（顶部铃铛） | 所有自动化事件 | 默认 |
| 钉钉/企微推送 | 交期预警、质量异常、急单插入 | 高 |
| 邮件 | 日报/周报汇总（后续） | 低 |

#### 4.11.2 通知内容模板

```
标题：订单 OD260616001 打板已确认，请生成采购计划
正文：
  客户：XX纺织有限公司
  面料：32S全棉汗布 黑色 180g/m²
  数量：5000kg | 交期：2026-07-15
  状态：打板确认 → 待采购
  操作：[去生成采购计划] [查看订单详情]
```

#### 4.11.3 通知偏好

- 用户可配置：哪些事件通知我、用什么渠道
- 通知已读/未读追踪
- 通知聚合：同类型多条合并（如「3个订单已到交期预警线」）

#### 4.11.4 实现要点 【v1.3 技术评审 P1-6】

```
系统内通知: t_notification 表写入 + 前端轮询 (30s 间隔 GET /api/v1/notifications/unread-count)
钉钉通知:   钉钉群机器人 Webhook（免费，Markdown 消息）
            Webhook URL 存系统参数表（支持按角色分群）
企微通知:   企业微信群机器人 Webhook（同上）
实现:      tex-erp-event 消费者发完系统通知后，异步调 Webhook
降级:      Webhook 失败仅记日志，不阻塞主流程、不重试
```

### 4.12 数据导入导出 【v1.1 新增】

> **为什么缺了不行**：迁移历史数据、导出给客户/老板看，全靠手写 SQL 不现实。

#### 4.12.1 Excel 导入

- 客户/供应商/物料/订单 支持 Excel 批量导入
- 导入模板下载（标准化表头）
- 导入校验 + 错误行高亮 + 支持逐行修正

#### 4.12.2 Excel 导出

- 订单列表导出（带筛选条件）
- 生产日报导出
- 库存报表导出
- 供应商/客户评分明细导出
- 质检报告导出（含 QC 标准对照）

### 4.13 样品/确样管理 【v1.2 P0】

> **为什么是P0**：打板产出样品 ≠ 客户确认。确样环节是订单确认的最后一关，没确样就进大货=找死。这是订单生命周期里最容易被忽略但出问题后果最严重的环节。

#### 4.13.1 打板 vs 确样

| | 打板 | 确样 |
|---|---|---|
| 发起方 | 内部 PMC | 客户确认后 |
| 产出物 | 样品实物 | 客户签回的确样单 |
| 流转方式 | 内部工单 | 寄出→客户审→寄回/确认 |
| 轮次 | 1次 | 可能2-3轮（修改重打） |

#### 4.13.2 确样流程

```
客户下订单 ──→ 打板 ──→ 寄样给客户 ──→ 客户确认 ──→ 大货生产
                                    │
                                    └── 客户退回修改 ──→ 重新打板 ──→ 再寄样
```

#### 4.13.3 核心功能

- 样品编号、版本号、寄出日期、预计到达日期
- 客户反馈记录（文字描述 + 照片上传）
- 确样状态：待寄出 / 客户审阅中 / 已确认 / 需修改
- 超N天未反馈 → 自动提醒跟单员催客户
- **确样确认后 → 自动触发 BOM 锁定**（禁止再改参数，防止客户反复修改）
- 确样记录关联打板工单，可追溯完整流转历史

### 4.14 色卡/Lab Dip 管理 【v1.2 P0】

> **为什么是P0**：纺织厂不管理颜色就是盲人开车。客户下单附带色卡标准（Pantone色号或实物色样），工厂出 Lab Dip（实验室小样染色）送客户确认。这个流程不管理，大货颜色偏差就是常态。

#### 4.14.1 核心场景

- 客户下单附带色卡标准（Pantone色号 或 实物色样）
- 工厂出 Lab Dip（实验室小样染色）送客户确认
- 客户确认 A/B/C 三个色中选 A → 大货按 A 的染料配方生产

#### 4.14.2 核心功能

- Lab Dip 编号、关联订单、色号（Pantone / 客户自定义 / Lab值）
- 多轮递色记录（第1轮→客户反馈→第2轮→确认）
- 确认后的染料配方锁定，生产时自动匹配
- 色卡实物照片存档（便于后续对色参考）

#### 4.14.3 数据价值（喂给 AI Agent）

AI Agent 可分析：
- 哪些颜色返工率高？（某色号多次递色才通过）
- 哪个客户对颜色最挑剔？（平均递色轮次）
- 哪种染料配方最稳定？（同色号多批次波动小）

### 4.15 裁床管理 【v1.2 P0】⭐

> **为什么是P0**：你每天用公式「日产量 ÷ 当天裁剪总量 = 裁床天数」在 Excel/WPS 里算。这是你日常工作流的核心环节，不进 ERP 系统就不算真正嵌入你的工作。

#### 4.15.1 ERP 化后的裁床流程

```
排产确认 → 自动生成裁床计划（面料用量+裁剪层数+预计耗时）
         → 裁床工单下发
         → 工人报工（裁剪完成数量）
         → 实时更新裁床进度
         → 自动关联到排产看板（裁床拖后腿 → 产线预警）
```

#### 4.15.2 核心数据

- 裁床编号、关联生产工单、面料/辅料清单
- 计划裁剪层数、实际裁剪层数、计划米数、实际米数
- 面料利用率 = 实际耗用/计划耗用 × 100%（高了=浪费，低了=省料）
- 裁床天数 = 日产量 ÷ 当天裁剪总量（公式内嵌到系统，自动计算）

#### 4.15.3 AI 可做的

- 面料利用率异常自动标记（某批面料利用率显著低于均值 → 可能是面料质量问题）
- 裁床产能趋势分析（跟产线能力分析类似逻辑，纳入产能画像）

### 4.16 计件工资 【v1.2 P1】

> **为什么是P1**：成本核算模块现有物料成本，缺人工成本。计件工资补上这块，排产→报工→工资数据链路打通。

#### 4.16.1 工资链路

```
工人报工（完成XX工序XX件）→ 自动按工序单价计算工资 → 月底汇总
```

#### 4.16.2 核心数据

- 工序单价表（不同工序、不同品类单价不同）
- 工人报工记录 → 日工资/月工资自动汇总
- 质检不合格扣款（联动 QC 记录）
- 与排产联动：排产时可预估该订单的人工成本

### 4.17 批号/缸号追溯 【v1.2 P1】

> **为什么是P1**：客户投诉有色差时，需要知道这批货用的是哪缸染的布、这缸布还用在哪些订单上、这批面料的供应商是谁。没有追溯链路，质量问题就是无头案。

#### 4.17.1 追溯链路

```
原料入库（批号+供应商）→ 染色（缸号）→ 裁床（裁床编号）→ 缝制（生产工单）→ 成品入库 → 出货
```

正向追（这缸布去了哪些订单）和反向追（这个订单用了哪些批次的料）都能查到。

#### 4.17.2 数据库要点

> **v1.3 修正**：原设计"在入库和生产表加 batch_no 字段"无法支持一对多/多对多追溯。改用关联表 `t_batch_trace`（建表 SQL 见 §7.2），每个流转节点插入一条记录，正向反向都可追溯。

### 4.18 对账单管理 【v1.2 P1】

> **为什么是P1**：客户分析 Agent 靠"付款及时率"评分，但如果连应收应付数据都没有，这个指标就是空壳。不做完整财务，只做业务对账。

#### 4.18.1 对账范围

- **客户对账单**：该客户本月下了多少单、发了多少货、应收多少、已收多少、欠多少
- **供应商对账单**：该供应商本月采购了多少、入库多少、应付多少、已付多少

#### 4.18.2 与 AI Agent 联动

- 客户付款及时率 → 客户评分 Agent 的核心输入
- 供应商价格稳定性 → 供应商评分 Agent 的输入
- 应收超N天未结 → 预警 Agent 自动提醒

### 4.19 司机绩效考核 【v1.2 P1】⭐

> **为什么是P1**：你每月从 WPS 多维表格拉数据做司机绩效表。ERP 化后出货单直接关联司机，月底一键导出绩效表。

#### 4.19.1 ERP 化后的流程

```
出货单 → 分配司机 → 记录发车/到达时间 → 客户签收 → 自动生成绩效数据
```

#### 4.19.2 考核指标

- 月运输趟数、总里程（如有GPS）/ 总重量
- 准时送达率
- 客户投诉次数
- 货损率
- 油耗/费用

月底一键导出绩效表，省掉你每月从 WPS 拉数据、手动汇总的重复劳动。

---

## 5. AI Agent 设计

### 5.1 Agent 架构

```
┌────────────────────────────────────────────┐
│              AI Agent 调度中心              │
│                                             │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
│  │ 客户分析 │ │ 供应商   │ │ 产线能力   │  │
│  │ Agent    │ │ 分析Agent│ │ 分析Agent  │  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘  │
│       │            │             │          │
│  ┌────┴────────────┴─────────────┴──────┐   │
│  │         评分引擎 (scikit-learn)       │   │
│  │   加权模型 + 规则引擎 + LLM解释       │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │         预警 Agent (定时巡检)         │   │
│  │   交期预警 / 质量异常 / 库存预警      │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │         自然语言查询接口              │   │
│  │   "最近一周哪个供应商出问题最多？"    │   │
│  └──────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

### 5.2 客户分析 Agent

#### 评分模型

```python
客户综合评分 = w1 × 付款及时率
            + w2 × 订单变更频率(反向)
            + w3 × 退货率(反向)
            + w4 × 利润贡献度
            + w5 × 沟通成本(改参数次数/投诉次数)

# 权重建议初始值
w = {"付款": 0.30, "变更": 0.20, "退货": 0.20, "利润": 0.15, "沟通": 0.15}
# 后续可通过历史数据回归调整
```

#### 难缠指数标签

| 分值区间 | 标签 | 建议策略 |
|----------|------|----------|
| 90-100 | 优质客户 | 正常合作 |
| 70-89 | 普通客户 | 关注沟通记录 |
| 50-69 | 需留意 | 关键节点书面确认 |
| <50 | 高风险 | 预付定金、合同加严 |

#### 数据来源

- 付款记录表 → 付款及时率
- 订单变更日志 → 变更频率
- 退货记录表 → 退货率
- 订单利润计算 → 利润贡献
- 沟通记录/钉钉消息(扩展) → 沟通成本

### 5.3 供应商分析 Agent

#### 评分模型

```python
供应商综合评分 = w1 × 质量合格率
              + w2 × 交期准时率
              + w3 × 价格竞争力
              + w4 × 服务配合度
              + w5 × 稳定性(长期方差)
```

#### 质量合格率计算

每批次到货质检后，自动更新：

```sql
-- 伪代码
供应商A质量合格率 = SUM(合格数量) / SUM(到货总数量) OVER 最近12个月
趋势分析：近3个月合格率 vs 前3个月 → 判断是否在恶化
```

#### 智能采购建议

当生成采购需求时，Agent 自动输出：
- 推荐供应商（按综合评分排序）
- 每个供应商的预计到货日期
- 近期质量波动提示（如"该供应商近2个月合格率下降10%"）
- 备选方案

### 5.4 产线能力分析 Agent

#### 分析维度

```python
产线能力画像 = {
    "日产能": 实际日产量(分面料类型)统计,
    "品质良率": 合格品/总产量,
    "擅长品类": 按面料类型分组统计效率最高的Top3,
    "交期达成率": 按时完工/总工单数,
    "当前负载": 已排单量/产能上限,
    "效率趋势": 近3个月产能变化(上升/稳定/下降)
}
```

#### 排产匹配算法

```python
def match_order_to_line(order, lines):
    """为订单推荐最优产线
    返回: List[(line, score)]，按 score 降序排列
    score 范围: 0-100，各维度返回值归一化到 0.0-1.0 后乘以权重
    """
    scores = []
    for line in lines:
        score = 0
        score += 30 * line.fabric_type_match(order.fabric)  # 品类匹配
        score += 25 * line.quality_rate                      # 品质良率
        score += 20 * (1 - line.current_load_rate)           # 剩余产能
        score += 15 * line.delivery_rate                     # 交期达成
        score += 10 * line.historical_efficiency(order.fabric) # 历史效率
        scores.append((line, score))
    return sorted(scores, key=lambda x: x[1], reverse=True)
```

### 5.5 预警 Agent（定时任务）

| 预警类型 | 触发条件 | 通知方式 |
|----------|----------|----------|
| 交期预警 | 距交期<N天 且 未开工 | 系统内标红 + 可选钉钉/企微通知 |
| 质量异常 | 某供应商近3批合格率骤降>20% | 标记该供应商 + 建议暂停采购 |
| 库存预警 | 某物料低于安全库存 | 提示采购 |
| 呆滞预警 | 库存>90天未动 | 报表标黄 |
| 产能预警 | 某产线下周排产已>120% | 提示调整或外发 |
| 客户异常 | 某客户30天内连续退货≥3次 | 标记风险客户 |

### 5.6 自然语言查询接口

通过 LLM 将自然语言转 SQL/分析指令：

```
用户：最近三个月，哪个供应商的面料问题最多？
Agent：查询质检不合格记录 → 按供应商分组统计 → 排序输出
  → "兴发纺织问题最多（6次不合格），主要问题：色差、门幅偏差。
      建议与该供应商沟通整改方案。"
```

### 5.7 AI 服务降级方案 【v1.3 技术评审 P1-4】

> Python AI 服务挂了，主系统不能跟着挂。必须有熔断降级。

```
Java 侧接入 Resilience4j CircuitBreaker:

AI 评分接口不可用时:
  → 返回缓存的上次评分 + 标注 "数据更新于 X 天前"

AI 采购推荐不可用时:
  → 降级为按历史采购价排序（纯查 MySQL，不依赖 AI）

AI 自然语言查询不可用时:
  → 返回 "AI 服务暂不可用，请使用常规查询功能"

预警 Agent:
  → 规则引擎兜底（交期 < 3天未开工、库存低于阈值等规则不依赖 AI）
  → AI 增强的预警（如质量异常趋势检测）静默跳过

熔断参数:
  failureRateThreshold: 50%     # 滑动窗口内 50% 失败就熔断
  waitDurationInOpenState: 60s  # 60 秒后半开试探
  slidingWindowSize: 10         # 最近 10 次请求统计
```

### 5.7.1 AI 服务间认证 【v1.5 新增】

> Java 调 Python AI 服务需认证，防止内网未授权调用。

```
方案：内部 API Key 认证
  - Java 和 Python 共享内部密钥（环境变量 AI_INTERNAL_KEY 注入）
  - Java 调 Python 时 Header 携带 X-Internal-Key: <key>
  - Python 用 FastAPI Dependency 校验，不通过返回 403
  - Nginx 层限制 /ai/* 只允许本机访问（deny all; allow 127.0.0.1）
```

### 5.7.2 AI 服务数据库连接 【v1.5 修正 A4】

> AI 服务需要两个数据库连接：只读查业务数据 + 读写写评分结果。

```
ai_readonly:  SQLAlchemy 引擎 → MySQL 用户 tex_ai_ro，只有 SELECT 权限
              用途：查订单、质检、库存等业务数据做分析

ai_write:     SQLAlchemy 引擎 → MySQL 用户 tex_ai_rw，有 SELECT + INSERT + UPDATE 权限
              用途：写入 t_customer_score / t_supplier_score / t_line_capability / t_score_feedback

权限粒度：MySQL 用户级别控制，最小权限原则
```

### 5.8 AI 评分模型评估 【v1.3 技术评审 P2-10】

> 评分准不准怎么衡量？需要收集用户反馈闭环优化。

每个评分展示旁加"👍 认可 / 👎 不认可"按钮。用户点击后记录到 `t_score_feedback` 表：

```sql
CREATE TABLE t_score_feedback (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    score_type      VARCHAR(32) COMMENT 'CUSTOMER/SUPPLIER/LINE',
    target_id       BIGINT COMMENT '客户/供应商/产线 ID',
    score_value     DECIMAL(5,2) COMMENT '当时的评分值',
    feedback        VARCHAR(16) COMMENT 'AGREE/DISAGREE',
    user_id         BIGINT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI评分用户反馈';
```

后续可据此计算"评分接受率"，调整模型权重。

---

## 6. 自动化算法设计

### 6.1 状态机驱动自动化

订单状态流转定义（v1.1 加入异常路径）：

```
                         ┌──────────┐
                         │  待审核   │──── 审核驳回 ────→ ┌──────────┐
                         └────┬─────┘                    │  已驳回   │
                              ↓ 审核通过                  └──────────┘
                         ┌──────────┐
                    ┌───→│  已确认   │──→ 自动创建参数模板
                    │    └────┬─────┘
                    │         ↓
  客户变更/修正参数  │    ┌──────────┐
   ←──────────────  ──── │  参数完成  │──→ 自动创建打板工单
                    │    └────┬─────┘
                    │         ↓
                    │    ┌──────────┐          ┌──────────┐
                    │    │  打板确认  │──→ 需重打──→│  重新打板  │
                    │    └────┬─────┘          └──────────┘
                    │         ↓ 客户确认
                    │    ┌──────────┐
                    │    │  采购中   │──→ 每日检查到货状态
                    │    └────┬─────┘
                    │         ↓
                    │    ┌──────────┐
                    │    │  物料齐套  │──→ 自动排入生产队列
                    │    └────┬─────┘
                    │         ↓
                    │    ┌──────────┐
                    │    │  生产中   │──→ 每日更新进度
                    │    └────┬─────┘
                    │         ↓
                    │    ┌──────────┐
                    │    │  已完成   │──→ 归档 + 更新客户/供应商评分
                    │    └──────────┘
                    │
  任何非终态 ───────┴──→ ┌──────────┐      ┌──────────┐
                          │  已取消   │      │  已暂停   │──── 恢复 ──→ 回到暂停前状态
                          └──────────┘      └──────────┘
```

**异常路径说明**：
- **已驳回**：审核不通过，可修改后重新提交
- **重新打板**：客户不满意样品，从打板节点重新来
- **已暂停**：客户要求暂停、付款未到等，可恢复
- **已取消**：最终废弃（仅非终态可取消，已完成的不允许取消）
- **参数回退**：打板/采购后发现参数有误，允许回到参数节点修正

状态变更时，发布 RabbitMQ 事件，消费者处理自动化逻辑。

### 6.2 关键自动化规则

| 规则ID | 触发条件 | 自动化动作 | 人工确认 |
|--------|----------|-----------|----------|
| AUTO-01 | 订单确认 | 创建参数录入任务 | 不需要 |
| AUTO-02 | 参数完成 | 创建打板工单 | 不需要 |
| AUTO-03 | 打板确认 | 生成采购需求 + 推荐供应商 | **需要**(确认采购单) |
| AUTO-04 | 全部到货质检合格 | 排入生产待排池 | 不需要 |
| AUTO-05 | 进入待排池 | 排产引擎自动分配产线+日期 | **需要**(确认排产计划) |
| AUTO-06 | 排产确认 | 生成每日生产工单 | 不需要 |
| AUTO-07 | 生产完成 | 通知质检 | 不需要 |
| AUTO-08 | 质检合格入库 | 通知可发货 | 不需要 |
| AUTO-09 | 距交期3天未开工 | 标红预警 + 推送 | - |
| AUTO-10 | 供应商连续2批不合格 | 标记"重点监控" | - |
| AUTO-11 | 订单暂停超过7天 | 提醒跟单确认是否取消 | - |
| AUTO-12 | 打板被拒(需重打) | 自动生成重打工单，原打板记录归档 | 不需要 |
| AUTO-13 | 订单取消 | 释放已占用物料、取消关联采购单、清理排产占位 | **需要**(二次确认) |
| AUTO-14 | 参数回退 | 废弃下游已生成但未执行的数据（删除未下单的采购计划） | **需要** |
| AUTO-15 | 质检不合格退货 | 自动扣供应商质量分 + 生成补货采购建议 | 不需要 |

### 6.3 订单变更管理 【v1.1 新增】

> **为什么缺了不行**：客户改数量、改交期、改规格是常态。没有变更流程，改一个字段下游全乱。

#### 6.3.1 变更类型与影响范围

| 变更类型 | 影响范围 | 处理策略 |
|----------|----------|----------|
| 数量增减 | 采购需求、排产计划 | 重算 BOM 用量，采购/排产增量调整 |
| 交期提前/延后 | 排产优先级 | 重排序，可能触发急单标签 |
| 规格修改(克重/门幅等) | BOM、参数、采购 | 回退到参数节点，重新走流程 |
| 取消部分 | 同上 + 库存释放 | 部分取消，已到货物料可用作备料 |

#### 6.3.2 变更流程

```
变更申请(跟单录入) → 系统计算影响范围 → 变更预览(哪些采购单/排产受影响)
→ 人工确认 → 批量执行变更 + 通知受影响环节负责人
```

#### 6.3.3 变更日志

- 每次变更记录：变更前值、变更后值、变更原因、操作人
- 纳入客户评分维度（变更频率越高，客户评分越低）

### 6.4 排产算法设计

```
算法：贪心 + 约束满足

输入：
  orders[]: 待排产订单（含交期、数量、面料类型、优先级）
  lines[]:  产线列表（含日产能、已排期、擅长品类）

步骤：
  1. 按 (交期紧迫度 × 优先级权重) 排序 orders
  2. For each order in orders:
     a. 筛选可生产该面料的产线
     b. 按产线匹配度排序
     c. 尝试插入最早可用时间段
     d. 如果超交期 → 标记风险，尝试拆分到多条产线
     e. 如果所有产线都排不下 → 人工决策（加班/外发/延期）
  3. 输出排程结果 + 产能利用率报表
  4. 生成甘特图数据

复杂度：O(n × m × log m)，n=订单数，m=产线数
适用规模：日排程 100+ 订单，10+ 产线，秒级出结果
```

### 6.5 并发控制策略 【v1.5 新增】

> ERP 核心场景涉及并发写入，不做并发控制 = 数据不一致。

| 场景 | 并发风险 | 控制方案 |
|------|----------|----------|
| 库存扣减/入库 | 超卖、重复入库 | 乐观锁（`version` 字段）+ 数据库行级锁 `SELECT ... FOR UPDATE` |
| 订单状态变更 | 两人同时操作同一订单 | 状态机校验 `from_status` + 乐观锁，变更时 WHERE version=? |
| 排产调整 | 多人同时拖拽甘特图 | 行锁 + 前端操作锁（Redis 分布式锁 `lock:schedule:{lineId}` TTL 30s） |
| 计件工资报工 | 重复报工 | 唯一约束 `(worker_id, production_id, process_step, report_date)` |
| 采购单确认 | 重复确认 | 状态机 + 乐观锁 |

**乐观锁实现（MyBatis-Plus @Version）：**
```java
@Version
private Integer version;
// UPDATE t_order SET status=?, version=version+1 WHERE id=? AND version=?
// 影响行数=0 → 抛出 OptimisticLockException → 前端提示"数据已被他人修改，请刷新后重试"
```

**统一审计字段规范 【v1.5新增】：**
所有业务表统一包含以下字段，由 MyBatis-Plus `MetaObjectHandler` 自动填充：
```sql
created_by  BIGINT COMMENT '创建人ID',
created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
updated_by  BIGINT COMMENT '更新人ID',
updated_at  DATETIME ON UPDATE CURRENT_TIMESTAMP,
deleted_at  DATETIME COMMENT '软删除时间 NULL=未删除（@TableLogic）'
```

---

## 7. 数据库设计

### 7.1 核心 ER 关系

```
customer ──┬── order ──┬── order_param
           │            │
           │            ├── proofing (打板)
           │            │
           │            ├── procurement_plan ──┬── purchase_order ── supplier
           │            │                      │
           │            │                      └── receiving (到货) ── qc_report
           │            │
           │            ├── production_schedule ── production_line
           │            │
           │            └── delivery (出库)
           │
           └── customer_score (客户评分，由Agent维护)
```

### 7.2 核心表结构

#### 用户表 (t_user)

```sql
CREATE TABLE t_user (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    username        VARCHAR(50) NOT NULL UNIQUE COMMENT '用户名',
    password        VARCHAR(200) NOT NULL COMMENT 'BCrypt加密密码',
    nickname        VARCHAR(50) COMMENT '昵称',
    email           VARCHAR(100) COMMENT '邮箱',
    phone           VARCHAR(20) COMMENT '手机号',
    status          TINYINT DEFAULT 1 COMMENT '0-禁用 1-启用',
    created_by      BIGINT COMMENT '创建人ID',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_by      BIGINT COMMENT '更新人ID',
    updated_at      DATETIME ON UPDATE CURRENT_TIMESTAMP,
    deleted_at      DATETIME COMMENT '软删除时间 NULL=未删除',
    UNIQUE KEY uk_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

#### 角色表 (t_role)

```sql
CREATE TABLE t_role (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    role_code       VARCHAR(50) NOT NULL UNIQUE COMMENT '角色编码 ROLE_ADMIN',
    role_name       VARCHAR(50) NOT NULL COMMENT '角色名称',
    description     VARCHAR(256) COMMENT '角色描述',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色表';
```

#### 用户角色关联表 (t_user_role)

```sql
CREATE TABLE t_user_role (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id         BIGINT NOT NULL,
    role_id         BIGINT NOT NULL,
    UNIQUE KEY uk_user_role (user_id, role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户角色关联';
```

#### 订单表 (t_order)

```sql
CREATE TABLE t_order (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_no        VARCHAR(32) NOT NULL UNIQUE COMMENT '订单号 OD260616001',
    customer_id     BIGINT NOT NULL COMMENT '客户ID',
    fabric_type     VARCHAR(64) COMMENT '面料类型',
    color           VARCHAR(32) COMMENT '颜色',
    weight_gm2      DECIMAL(8,2) COMMENT '克重 g/m²',
    width_cm        DECIMAL(8,2) COMMENT '门幅 cm',
    quantity_kg     DECIMAL(12,2) COMMENT '数量(kg)',
    order_amount    DECIMAL(12,2) COMMENT '订单金额(元) 【v1.3新增】',
    currency        VARCHAR(8) DEFAULT 'CNY' COMMENT '币种 CNY/USD/KHR 【v1.5新增-柬埔寨部署】',
    delivery_date   DATE COMMENT '交期',
    priority        TINYINT DEFAULT 0 COMMENT '优先级 0普通 1急单 2特急',
    status          VARCHAR(32) NOT NULL COMMENT '状态见状态机',
    version         INT DEFAULT 0 COMMENT '乐观锁版本号 【v1.5新增-并发控制】',
    confirmed_at    DATETIME COMMENT '确认时间 【v1.3新增】',
    completed_at    DATETIME COMMENT '完成时间 【v1.3新增】',
    remark          TEXT,
    created_by      BIGINT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_by      BIGINT COMMENT '更新人ID 【v1.5新增】',
    updated_at      DATETIME ON UPDATE CURRENT_TIMESTAMP,
    deleted_at      DATETIME COMMENT '软删除时间 NULL=未删除 【v1.5新增】',
    INDEX idx_status (status),
    INDEX idx_customer (customer_id),
    INDEX idx_delivery (delivery_date),
    INDEX idx_status_delivery (status, delivery_date)  /* 【v1.3新增】排产待排池高频查询 */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';
```

> **v1.3 说明**：原有的 `customer_risk` 字段删除，改为查询时 JOIN `t_customer_score` 获取实时评分。冗余字段必然不同步。

#### 订单状态变更日志 (t_order_status_log)

```sql
CREATE TABLE t_order_status_log (
    id            BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id      BIGINT NOT NULL,
    from_status   VARCHAR(32),
    to_status     VARCHAR(32) NOT NULL,
    operator_id   BIGINT COMMENT '操作人 0=系统自动',
    operator_type VARCHAR(16) COMMENT 'HUMAN/AUTO',
    remark        TEXT,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单状态变更日志';
```

#### 供应商评分表 (t_supplier_score) — Agent 维护

```sql
CREATE TABLE t_supplier_score (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    supplier_id         BIGINT NOT NULL,
    quality_rate        DECIMAL(5,4) COMMENT '质量合格率 0-1',
    delivery_rate       DECIMAL(5,4) COMMENT '交期准时率',
    price_stability     DECIMAL(5,4) COMMENT '价格稳定性',
    service_score       DECIMAL(5,4) COMMENT '配合度评分',
    composite_score     DECIMAL(5,2) COMMENT '综合评分 0-100',
    sample_count        INT COMMENT '样本量(批次)',
    trend               VARCHAR(16) COMMENT '趋势: UP/STABLE/DOWN',
    risk_flag           VARCHAR(16) COMMENT 'NORMAL/WARNING/DANGER',
    is_latest           TINYINT DEFAULT 1 COMMENT '1=最新版本 0=历史版本 【v1.5新增】',
    calculated_at       DATETIME COMMENT '计算时间',
    INDEX idx_supplier_latest (supplier_id, is_latest),
    INDEX idx_supplier_time (supplier_id, calculated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='供应商评分(AI维护, 追加式写入保留历史)';
```

#### 客户评分表 (t_customer_score) — Agent 维护

```sql
CREATE TABLE t_customer_score (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    customer_id         BIGINT NOT NULL,
    payment_rate        DECIMAL(5,4) COMMENT '付款及时率',
    change_freq         DECIMAL(8,2) COMMENT '订单变更频率(次/月)',
    return_rate         DECIMAL(5,4) COMMENT '退货率',
    profit_contribution DECIMAL(12,2) COMMENT '利润贡献',
    communication_cost  DECIMAL(5,2) COMMENT '沟通成本评分',
    composite_score     DECIMAL(5,2) COMMENT '综合评分 0-100',
    difficulty_label    VARCHAR(16) COMMENT '标签: EASY/NORMAL/WATCH/RISKY',
    is_latest           TINYINT DEFAULT 1 COMMENT '1=最新版本 0=历史版本 【v1.5新增】',
    calculated_at       DATETIME,
    INDEX idx_customer_latest (customer_id, is_latest),
    INDEX idx_customer_time (customer_id, calculated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='客户评分(AI维护, 追加式写入保留历史)';
```

#### 产线能力表 (t_line_capability) — Agent 维护

```sql
CREATE TABLE t_line_capability (
    id                BIGINT PRIMARY KEY AUTO_INCREMENT,
    line_id           BIGINT NOT NULL,
    fabric_type       VARCHAR(64) NOT NULL COMMENT '面料类型',
    daily_capacity_kg DECIMAL(10,2) COMMENT '日产能(kg)',
    quality_rate      DECIMAL(5,4) COMMENT '品质良率',
    delivery_rate     DECIMAL(5,4) COMMENT '交期达成率',
    efficiency_trend  VARCHAR(16) COMMENT '效率趋势',
    is_latest         TINYINT DEFAULT 1 COMMENT '1=最新版本 0=历史版本 【v1.5新增】',
    calculated_at     DATETIME,
    INDEX idx_line_fabric_latest (line_id, fabric_type, is_latest),
    INDEX idx_line_time (line_id, calculated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='产线能力(AI维护, 追加式写入保留历史)';
```

#### BOM 主表 (t_bom) 【v1.1 新增】

```sql
CREATE TABLE t_bom (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    bom_code        VARCHAR(32) NOT NULL COMMENT 'BOM编号',
    fabric_type     VARCHAR(64) NOT NULL COMMENT '面料类型',
    version         VARCHAR(16) NOT NULL DEFAULT '1.0' COMMENT '版本号',
    status          VARCHAR(16) DEFAULT 'DRAFT' COMMENT 'DRAFT/PROD/OBSOLETE',
    total_loss_rate DECIMAL(5,4) DEFAULT 0 COMMENT '总损耗率',
    copied_from     BIGINT COMMENT '复制来源BOM ID 【v1.3新增】',
    created_by      BIGINT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_bom_version (fabric_type, version),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='BOM主表';
```

#### BOM 明细表 (t_bom_item) 【v1.1 新增】

```sql
CREATE TABLE t_bom_item (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    bom_id          BIGINT NOT NULL COMMENT 'BOM主表ID',
    material_id     BIGINT NOT NULL COMMENT '物料ID',
    material_type   VARCHAR(32) COMMENT 'YARN/DYE/AUXILIARY/PACKAGE',
    quantity_per    DECIMAL(12,4) COMMENT '单位用量(每kg面料用量)',
    unit            VARCHAR(16) COMMENT '单位 kg/g/m/个',
    process_step    VARCHAR(32) COMMENT '关联工序: DYEING/WEAVING/FINISHING',
    sort_order      INT DEFAULT 0,
    INDEX idx_bom (bom_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='BOM明细表';
```

#### 订单成本表 (t_order_cost) 【v1.1 新增】

```sql
CREATE TABLE t_order_cost (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id            BIGINT NOT NULL UNIQUE,
    material_cost       DECIMAL(12,2) DEFAULT 0 COMMENT '原料成本',
    labor_cost          DECIMAL(12,2) DEFAULT 0 COMMENT '人工成本',
    manufacturing_cost  DECIMAL(12,2) DEFAULT 0 COMMENT '制造费用',
    outsourcing_cost    DECIMAL(12,2) DEFAULT 0 COMMENT '外发费用',
    loss_cost           DECIMAL(12,2) DEFAULT 0 COMMENT '损耗成本',
    packaging_cost      DECIMAL(12,2) DEFAULT 0 COMMENT '包装成本',
    logistics_cost      DECIMAL(12,2) DEFAULT 0 COMMENT '物流成本',
    total_cost          DECIMAL(12,2) DEFAULT 0 COMMENT '总成本',
    gross_profit        DECIMAL(12,2) COMMENT '毛利(计算时从t_order.order_amount获取)',
    profit_rate         DECIMAL(5,4) COMMENT '毛利率',
    calculated_at       DATETIME,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单成本表';
```

#### QC 标准模板表 (t_qc_standard) 【v1.1 新增】

```sql
CREATE TABLE t_qc_standard (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    name            VARCHAR(64) NOT NULL COMMENT '标准名称',
    customer_id     BIGINT COMMENT '关联客户(客户专属标准)',
    is_default      TINYINT DEFAULT 0 COMMENT '是否该客户默认标准',
    status          VARCHAR(16) DEFAULT 'ACTIVE',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='QC标准模板';
```

#### QC 标准检查项 (t_qc_standard_item) 【v1.1 新增】

```sql
CREATE TABLE t_qc_standard_item (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    standard_id     BIGINT NOT NULL,
    item_name       VARCHAR(64) NOT NULL COMMENT '检查项: 色牢度/色差/门幅偏差/外观疵点',
    check_type      VARCHAR(16) DEFAULT 'RANGE' COMMENT '判定方式: RANGE(范围)/BOOLEAN(合格不合格)/ENUM(枚举)/TEXT(文字描述) 【v1.5新增】',
    item_unit       VARCHAR(16) COMMENT '单位',
    min_value       DECIMAL(10,4) COMMENT '合格下限(RANGE类型用)',
    max_value       DECIMAL(10,4) COMMENT '合格上限(RANGE类型用)',
    pass_value      VARCHAR(64) COMMENT '合格值(BOOLEAN=pass/fail, ENUM=逗号分隔合格值) 【v1.5新增】',
    INDEX idx_standard (standard_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='QC标准检查项';
```

#### 通知记录表 (t_notification) 【v1.1 新增】

```sql
CREATE TABLE t_notification (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id         BIGINT NOT NULL COMMENT '接收人',
    title           VARCHAR(256) NOT NULL,
    content         TEXT,
    notify_type     VARCHAR(32) COMMENT 'DELIVERY_ALERT/QUALITY_ALERT/STATUS_CHANGE',
    channel         VARCHAR(32) COMMENT 'SYSTEM/DINGTALK/WECOM',
    ref_type        VARCHAR(32) COMMENT '关联类型: ORDER/PROCUREMENT',
    ref_id          BIGINT COMMENT '关联ID',
    is_read         TINYINT DEFAULT 0,
    read_at         DATETIME,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_read (user_id, is_read),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='通知记录表';
```

#### 外发加工单表 (t_outsource_order) 【v1.1 新增】

```sql
CREATE TABLE t_outsource_order (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    outsource_no    VARCHAR(32) NOT NULL UNIQUE COMMENT '外发单号',
    order_id        BIGINT COMMENT '关联订单',
    outsourcer_id   BIGINT NOT NULL COMMENT '外发厂ID',
    fabric_type     VARCHAR(64),
    quantity_kg     DECIMAL(12,2),
    status          VARCHAR(32) COMMENT '待发料/外发中/已回收/已结算',
    send_date       DATE COMMENT '发料日期',
    return_date     DATE COMMENT '回收日期',
    price           DECIMAL(12,2) COMMENT '加工费',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='外发加工单';
```

#### 订单变更记录表 (t_order_change_log) 【v1.1 新增】

```sql
CREATE TABLE t_order_change_log (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id        BIGINT NOT NULL,
    change_type     VARCHAR(32) COMMENT 'QUANTITY/DELIVERY/SPEC/CANCEL',
    field_name      VARCHAR(64) COMMENT '变更字段',
    old_value       TEXT,
    new_value       TEXT,
    affect_summary  TEXT COMMENT '影响范围摘要(JSON)',
    operator_id     BIGINT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单变更记录';
```

#### 确样记录表 (t_sample_approval) 【v1.2 P0 新增】

```sql
CREATE TABLE t_sample_approval (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id        BIGINT NOT NULL,
    sample_no       VARCHAR(32) NOT NULL COMMENT '样品编号',
    version         INT DEFAULT 1 COMMENT '第几版样品',
    proofing_id     BIGINT COMMENT '关联打板工单',
    send_date       DATE COMMENT '寄出日期',
    estimated_arrival DATE COMMENT '预计到达日期',
    tracking_no     VARCHAR(64) COMMENT '快递单号',
    status          VARCHAR(32) COMMENT '待寄出/客户审阅中/已确认/需修改',
    customer_feedback TEXT COMMENT '客户反馈',
    feedback_photos VARCHAR(1024) COMMENT '反馈照片URL(JSON数组)',
    confirmed_at    DATETIME COMMENT '确认时间',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='样品确样记录';
```

#### Lab Dip 记录表 (t_lab_dip) 【v1.2 P0 新增】

```sql
CREATE TABLE t_lab_dip (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id        BIGINT NOT NULL,
    dip_no          VARCHAR(32) NOT NULL COMMENT '递色编号',
    round           INT DEFAULT 1 COMMENT '第几轮递色',
    pantone_code    VARCHAR(32) COMMENT 'Pantone色号',
    lab_l           DECIMAL(6,2) COMMENT 'Lab-L值',
    lab_a           DECIMAL(6,2) COMMENT 'Lab-a值',
    lab_b           DECIMAL(6,2) COMMENT 'Lab-b值',
    dye_formula     TEXT COMMENT '染料配方(JSON)',
    status          VARCHAR(32) COMMENT '待寄出/客户审阅中/已确认/需重调',
    customer_feedback TEXT,
    confirmed_at    DATETIME,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Lab Dip递色记录';
```

#### 裁床工单表 (t_cutting_order) 【v1.2 P0 新增】

```sql
CREATE TABLE t_cutting_order (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    cutting_no      VARCHAR(32) NOT NULL UNIQUE COMMENT '裁床编号',
    production_id   BIGINT NOT NULL COMMENT '关联生产工单',
    plan_layers     INT COMMENT '计划层数',
    actual_layers   INT COMMENT '实际层数',
    plan_meters     DECIMAL(12,2) COMMENT '计划米数',
    actual_meters   DECIMAL(12,2) COMMENT '实际米数',
    fabric_utilization DECIMAL(5,4) COMMENT '面料利用率',
    daily_output    DECIMAL(10,2) COMMENT '日产量',
    cutting_days    DECIMAL(5,2) COMMENT '裁床天数(自动计算)',
    status          VARCHAR(32) COMMENT '待裁剪/裁剪中/已完成',
    started_at      DATETIME,
    completed_at    DATETIME,
    INDEX idx_production (production_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='裁床工单';
```

#### 计件工资记录表 (t_piece_wage) 【v1.2 P1 新增】

```sql
CREATE TABLE t_piece_wage (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    worker_id       BIGINT NOT NULL COMMENT '工人ID',
    production_id   BIGINT COMMENT '关联生产工单',
    process_step    VARCHAR(32) COMMENT '工序',
    quantity        DECIMAL(10,2) COMMENT '完成数量',
    unit_price      DECIMAL(8,4) COMMENT '工序单价',
    wage_amount     DECIMAL(10,2) COMMENT '工资金额',
    qc_deduction    DECIMAL(10,2) DEFAULT 0 COMMENT '质检扣款',
    report_date     DATE COMMENT '报工日期',
    INDEX idx_worker_date (worker_id, report_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='计件工资记录';
```

#### 工序单价表 (t_process_price) 【v1.2 P1 新增】

```sql
CREATE TABLE t_process_price (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    process_step    VARCHAR(32) NOT NULL COMMENT '工序: CUTTING/SEWING/DYEING',
    fabric_type     VARCHAR(64) COMMENT '面料类型(可为空=通用)',
    unit_price      DECIMAL(8,4) NOT NULL COMMENT '单价(元/件或元/kg)',
    unit            VARCHAR(16) COMMENT '计价单位',
    effective_from  DATE,
    INDEX idx_process (process_step, fabric_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='工序单价表';
```

#### 对账单表 (t_statement) 【v1.2 P1 新增】

```sql
CREATE TABLE t_statement (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    statement_type  VARCHAR(16) NOT NULL COMMENT 'CUSTOMER/SUPPLIER',
    target_id       BIGINT NOT NULL COMMENT '客户ID或供应商ID',
    period_start    DATE NOT NULL COMMENT '账期开始',
    period_end      DATE NOT NULL COMMENT '账期结束',
    opening_balance DECIMAL(12,2) DEFAULT 0 COMMENT '期初余额',
    total_debit     DECIMAL(12,2) DEFAULT 0 COMMENT '本期借方(应收/应付)',
    total_credit    DECIMAL(12,2) DEFAULT 0 COMMENT '本期贷方(已收/已付)',
    closing_balance DECIMAL(12,2) DEFAULT 0 COMMENT '期末余额',
    status          VARCHAR(16) DEFAULT 'OPEN' COMMENT 'OPEN/CLOSED',
    INDEX idx_target (target_id, period_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='对账单';
```

#### 司机绩效表 (t_driver_performance) 【v1.2 P1 新增】

```sql
CREATE TABLE t_driver_performance (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    driver_id       BIGINT NOT NULL COMMENT '司机ID',
    period_month    VARCHAR(7) NOT NULL COMMENT '考核月份 YYYY-MM',
    trip_count      INT DEFAULT 0 COMMENT '运输趟数',
    total_weight    DECIMAL(12,2) DEFAULT 0 COMMENT '总重量(kg)',
    ontime_rate     DECIMAL(5,4) COMMENT '准时送达率',
    complaint_count INT DEFAULT 0 COMMENT '客户投诉次数',
    damage_rate     DECIMAL(5,4) COMMENT '货损率',
    fuel_cost       DECIMAL(10,2) COMMENT '油耗/费用',
    overall_score   DECIMAL(5,2) COMMENT '综合评分',
    UNIQUE KEY uk_driver_month (driver_id, period_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='司机月度绩效考核';
```

#### 收付款记录表 (t_payment) 【v1.3 技术评审 P0-3】

> 客户评分"付款及时率"需要有逐笔收付款记录。不走银行接口，纯人工记账。

```sql
CREATE TABLE t_payment (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    payment_no      VARCHAR(32) NOT NULL UNIQUE COMMENT '收付单号 PAY260616001',
    payment_type    VARCHAR(16) NOT NULL COMMENT 'RECEIVE(客户付款)/PAY(付供应商)',
    target_id       BIGINT NOT NULL COMMENT '客户ID 或 供应商ID',
    order_id        BIGINT COMMENT '关联订单ID(收款时)',
    purchase_id     BIGINT COMMENT '关联采购单ID(付款时)',
    amount          DECIMAL(12,2) NOT NULL COMMENT '金额',
    payment_date    DATE NOT NULL COMMENT '收付日期',
    remark          TEXT COMMENT '备注（如：银行转账/现金/微信）',
    created_by      BIGINT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_target (target_id, payment_date),
    INDEX idx_order (order_id),
    INDEX idx_purchase (purchase_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收付款记录(纯记账)';
```

付款及时率计算公式：
```
客户付款及时率 = 按时付款次数 / 应收总次数
"按时" = payment_date ≤ (订单完成日期 + 客户账期天数)

供应商付款情况（反过来看自己是否及时付款给供应商）：
应付按时率 = 按时付款次数 / 应付总次数
```

#### 批次追溯关联表 (t_batch_trace) 【v1.3 技术评审 P1-5】

> 原 §4.17 设计"在入库和生产表加字段"无法支持多对多追溯。一缸染料→多批布→多个订单，必须用关联表。

```sql
CREATE TABLE t_batch_trace (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    batch_no        VARCHAR(64) NOT NULL COMMENT '原料批号',
    dye_lot_no      VARCHAR(64) COMMENT '染缸号(染色后生成)',
    receipt_id      BIGINT COMMENT '到货记录ID',
    production_id   BIGINT COMMENT '生产工单ID',
    cutting_id      BIGINT COMMENT '裁床工单ID',
    out_quantity    DECIMAL(12,2) COMMENT '流出数量(kg)',
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_batch (batch_no),
    INDEX idx_dye_lot (dye_lot_no),
    INDEX idx_production (production_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='批次追溯关联表';
```

追溯能力：
- **正向**：原料批号 → 染缸号 → 哪个工单 → 哪个裁床 → 成品
- **反向**：客户投诉某订单 → 查到用了哪缸染的 → 该缸还用在哪些其他订单上

#### 产线日历表 (t_line_calendar) 【v1.3 技术评审 P1-1】

> 排产算法需要知道哪些天不工作（节假日、检修日、周日休息）。

```sql
CREATE TABLE t_line_calendar (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    line_id         BIGINT NOT NULL COMMENT '产线ID(0=全厂通用)',
    calendar_date   DATE NOT NULL COMMENT '日期',
    is_workday      TINYINT DEFAULT 1 COMMENT '1工作日 0休息日',
    shift_count     TINYINT DEFAULT 1 COMMENT '班次数',
    work_hours      DECIMAL(4,1) DEFAULT 8.0 COMMENT '工作时长',
    remark          VARCHAR(128) COMMENT '如：国庆放假/设备检修',
    UNIQUE KEY uk_line_date (line_id, calendar_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='产线工作日历';
```

> 其他表：客户表、供应商表、物料表、采购单表、入库单表、出库单表、质检单表、产线表、生产工单表、用户表、角色表等，按规范设计，此处不全部展开。

---

## 8. API 接口设计

### 8.1 RESTful 规范

```
统一前缀：/api/v1
统一响应：{ "code": 200, "message": "success", "data": {...} }
分页响应：{ "code": 200, "data": { "records": [...], "total": 100, "page": 1, "size": 20 } }
```

### 8.2 核心 API 列表

#### 订单模块

```
POST   /api/v1/orders                   创建订单
GET    /api/v1/orders                   订单列表(分页+筛选)
GET    /api/v1/orders/{id}              订单详情
PUT    /api/v1/orders/{id}              更新订单
PUT    /api/v1/orders/{id}/status       变更订单状态
GET    /api/v1/orders/{id}/timeline     订单时间线(状态变更日志)
DELETE /api/v1/orders/{id}              删除订单(仅待审核状态)
```

#### 参数/打板

```
POST   /api/v1/orders/{id}/params       录入/更新参数
GET    /api/v1/orders/{id}/params       查询参数
POST   /api/v1/orders/{id}/proofing     创建打板工单
PUT    /api/v1/proofing/{id}/status     更新打板状态
GET    /api/v1/orders/{id}/proofing     查询打板记录
```

#### 采购模块

```
POST   /api/v1/procurement/plans        生成采购计划(AI推荐)
GET    /api/v1/procurement/plans/{id}   查看采购计划
POST   /api/v1/procurement/orders       创建采购单
PUT    /api/v1/procurement/orders/{id}  更新采购单
POST   /api/v1/receiving                到货登记
POST   /api/v1/receiving/{id}/qc        质检登记
```

#### 仓库模块

```
GET    /api/v1/inventory                 库存查询
GET    /api/v1/inventory/alerts          库存预警列表
POST   /api/v1/warehouse/in              入库操作
POST   /api/v1/warehouse/out             出库操作
```

#### 排产模块

```
GET    /api/v1/production/pool           待排产订单池
POST   /api/v1/production/schedule       执行排产算法
GET    /api/v1/production/schedule       查看排产结果(甘特图数据)
PUT    /api/v1/production/schedule/{id}  手动调整排产
POST   /api/v1/production/schedule/confirm 确认排产计划
GET    /api/v1/production/daily/{date}   某日产线任务
```

#### AI 分析接口

```
GET    /api/v1/ai/customer/{id}/score       客户评分详情
GET    /api/v1/ai/supplier/{id}/score       供应商评分详情
GET    /api/v1/ai/line/{id}/capability      产线能力分析
GET    /api/v1/ai/procurement/recommend     采购智能推荐(传入订单ID)
GET    /api/v1/ai/schedule/optimize         排产优化建议
GET    /api/v1/ai/alerts                    当前活跃预警列表
POST   /api/v1/ai/query                     自然语言查询
```

#### BOM 管理 【v1.1 新增】

```
GET    /api/v1/bom                             BOM列表(按面料类型)
POST   /api/v1/bom                             创建BOM
GET    /api/v1/bom/{id}                        BOM详情(含明细)
PUT    /api/v1/bom/{id}                        更新BOM(自动升版本)
POST   /api/v1/bom/{id}/activate              激活为量产版
GET    /api/v1/bom/{id}/versions              版本历史
```

#### 成本管理 【v1.1 新增】

```
GET    /api/v1/cost/order/{id}                 订单成本详情
POST   /api/v1/cost/order/{id}/calculate       重新计算订单成本
GET    /api/v1/cost/summary                    成本汇总(按时间段/客户)
```

#### QC 标准 【v1.1 新增】

```
GET    /api/v1/qc/standards                    QC标准模板列表
POST   /api/v1/qc/standards                    创建QC标准
GET    /api/v1/qc/standards/{id}               标准详情(含检查项)
PUT    /api/v1/qc/standards/{id}               更新标准
```

#### 外发加工 【v1.1 新增】

```
GET    /api/v1/outsource                       外发单列表
POST   /api/v1/outsource                       创建外发单
PUT    /api/v1/outsource/{id}/status           更新外发状态
GET    /api/v1/outsource/suggestions/{orderId} 外发厂推荐(产能不足时)
```

#### 通知中心 【v1.1 新增】

```
GET    /api/v1/notifications                   我的通知列表
PUT    /api/v1/notifications/{id}/read         标记已读
POST   /api/v1/notifications/read-all          全部已读
GET    /api/v1/notifications/unread-count      未读数量
```

#### 工作台 【v1.1 新增】

```
GET    /api/v1/dashboard/overview              全局仪表盘数据(KPI卡片+趋势)
GET    /api/v1/dashboard/my-tasks               我的待办(按角色)
```

#### 数据导入导出 【v1.1 新增】

```
POST   /api/v1/import/{entity}                 批量导入(entity: order/supplier等)
GET    /api/v1/import/template/{entity}        下载导入模板
GET    /api/v1/export/orders                   导出订单
GET    /api/v1/export/inventory                导出库存
GET    /api/v1/export/production/{date}        导出生产日报
```

#### 样品确样 【v1.2 P0 新增】

```
POST   /api/v1/orders/{id}/samples             创建确样记录(寄出)
PUT    /api/v1/samples/{id}/feedback            录入客户反馈
PUT    /api/v1/samples/{id}/confirm             确认样品通过
GET    /api/v1/orders/{id}/samples              查看订单所有确样记录
```

#### 色卡/Lab Dip 【v1.2 P0 新增】

```
POST   /api/v1/orders/{id}/lab-dips             创建递色记录
PUT    /api/v1/lab-dips/{id}/feedback            录入客户反馈
PUT    /api/v1/lab-dips/{id}/confirm             确认色样
GET    /api/v1/orders/{id}/lab-dips              查看订单所有递色记录
```

#### 裁床管理 【v1.2 P0 新增】

```
GET    /api/v1/cutting                          裁床工单列表
POST   /api/v1/cutting                          生成裁床计划(从排产触发)
PUT    /api/v1/cutting/{id}/progress             更新裁剪进度
GET    /api/v1/cutting/daily/{date}              某日裁床日报
GET    /api/v1/cutting/{id}/utilization          面料利用率分析
```

#### 计件工资 【v1.2 P1 新增】

```
GET    /api/v1/wages/process-prices              工序单价列表
POST   /api/v1/wages/process-prices              设置工序单价
POST   /api/v1/wages/report                      工人报工
GET    /api/v1/wages/worker/{id}/monthly/{month} 工人月度工资汇总
GET    /api/v1/wages/summary/{month}             全厂月度工资汇总
```

#### 对账单 【v1.2 P1 新增】

```
GET    /api/v1/statements/customer/{id}          客户对账单
GET    /api/v1/statements/supplier/{id}          供应商对账单
POST   /api/v1/statements/generate               生成月度对账单
GET    /api/v1/statements/receivable-alerts      应收超期预警
```

#### 司机绩效 【v1.2 P1 新增】

```
GET    /api/v1/drivers                           司机列表
POST   /api/v1/deliveries/{id}/assign-driver     分配司机
PUT    /api/v1/deliveries/{id}/sign               签收登记
GET    /api/v1/drivers/{id}/performance/{month}  司机月度绩效
GET    /api/v1/drivers/performance/export/{month} 导出绩效表
```

#### 认证接口 【v1.3 新增】

```
POST   /api/v1/auth/login                    登录
POST   /api/v1/auth/refresh                  刷新 Access Token
POST   /api/v1/auth/logout                   退出（Refresh Token 加入黑名单）
GET    /api/v1/auth/me                       当前用户信息+权限
```

#### 文件管理 【v1.3 技术评审 P1-7】

```
POST   /api/v1/files/presign                 获取预签名上传URL(前端直传MinIO)
GET    /api/v1/files/{fileKey}/download      获取预签名下载URL
DELETE /api/v1/files/{fileKey}               删除文件
```

前端上传流程：调 presign 获取临时 URL → 前端直接 PUT 到 MinIO → 返回 fileKey 存到业务表（如 QC 照片字段）。

#### 批量操作 【v1.3 技术评审 P2-4】

```
PUT    /api/v1/orders/batch-status            批量变更订单状态
PUT    /api/v1/orders/batch-assign            批量分配跟单员
GET    /api/v1/export/orders-batch            批量导出订单(勾选导出)
```

### 8.3 AI 查询接口示例

```json
// POST /api/v1/ai/query
{
  "question": "最近一个月哪个供应商质量最差"
}

// Response
{
  "code": 200,
  "data": {
    "answer": "兴发纺织近30天到货5批，不合格2批（合格率60%），主要问题为色差超标。已自动标记为重点监控。",
    "related_data": {
      "supplier": "兴发纺织",
      "total_batches": 5,
      "fail_batches": 2,
      "fail_reasons": ["色差超标(2次)"],
      "status": "WARNING"
    }
  }
}
```

---

## 9. 开发路线图

### 阶段一：基础骨架（预计 2 周）

```
Week 1-2:
├── 项目脚手架搭建（Spring Boot + Vue3 + 基础配置）
├── JWT 认证 + RBAC 权限（登录/Token刷新/角色）
├── SpringDoc OpenAPI 接入（Swagger 文档自动生成）
├── Docker Compose 开发环境就绪（MySQL/Redis/RabbitMQ/MinIO）
├── Flyway 初始化 + 全量表建表（含 v1.3 新增表）
├── 基础数据管理（客户、供应商、物料、产线、工人、司机 CRUD）
├── 数据字典初始化（面料类型/颜色/QC检查项等枚举 INSERT）
├── 物料单位换算配置
├── QC 标准模板 CRUD
├── 工序单价配置
├── 通知中心基础（系统内通知+未读计数）
└── 前后端联调打通
```

**交付物**：可登录、管理基础数据的管理后台 + Swagger文档 + Docker开发环境

### 阶段二：核心流程（预计 4 周）【v1.3 调整 3周→4周】

```
Week 3-6:
├── 订单管理：下单 → 参数 → 打板 全流程（含异常路径）
├── 样品/确样管理：确样记录、客户反馈、确认流程
├── 色卡/Lab Dip管理：递色记录、配方锁定、多轮确认
├── BOM 管理：创建/版本管理/激活/复制
├── 采购管理：BOM 自动算需求 → 采购单 → 到货 → 质检
├── 仓库管理：入库 / 出库 / 库存查询（含 MinIO 文件上传）
├── 批号/缸号追溯（t_batch_trace 关联表实现）
├── 订单状态机（含异常路径）+ 状态变更日志
├── 订单变更管理：申请→影响预览→确认
├── 事件驱动：状态变更 → RabbitMQ → 自动化编排
└── 数据导入（Excel 批量导入客户/供应商/物料）
```

**交付物**：核心业务流程可跑通（= 系统已可独立交付）

### 阶段三：排产引擎 + 成本外发（预计 3 周）【v1.3 调整 2周→3周】

```
Week 7-9:
├── 排产算法实现（贪心+约束+产线日历）
├── 排产看板（甘特图）+ 手动拖拽调整
├── 生产工单生成
├── 产线产能管理 + 产线日历维护
├── 裁床管理：计划生成→工单→进度→裁床天数自动计算
├── 外发加工管理：需求识别→发料→回收→结算
├── 司机绩效考核：出货→分配司机→签收→绩效汇总
├── 计件工资：报工→工资计算→月底汇总
├── 对账单：应收应付统计 + 收付款记账
├── 成本核算：BOM+采购价+工价 → 订单成本
└── 工作台首页（按角色展示待办/指标）
```

**交付物**：排产+成本+外发+对账模块上线

### 阶段四：AI Agent（预计 4 周）【v1.3 调整 3周→4周】

```
Week 10-13:
├── Python AI 服务搭建（FastAPI + Resilience4j 熔断）
├── 客户评分 Agent + 评分模型（含利润贡献=真实成本+对账单+收付款记录）
├── 供应商评分 Agent + 质量趋势（含批号追溯数据）
├── 产线能力分析 Agent（含裁床数据）
├── 裁床面料利用率异常分析
├── 色卡数据分析：返工率高的颜色、挑剔的客户、稳定的配方
├── 智能采购推荐（含外发厂推荐）
├── 智能排产建议（产线匹配度评分）
├── 预警 Agent（定时巡检+通知推送+应收超期预警）
├── 自然语言查询接口（DeepSeek）
├── AI 评分反馈收集（👍👎按钮）
├── AI 桥接层（Java 调 Python + 熔断降级 + 缓存）
└── 仪表盘图表（ECharts 趋势图/供应商排行/产能/司机绩效排行）
```

**交付物**：AI 分析中心上线 + 完整仪表盘

### 阶段五：打磨上线（预计 3 周）【v1.3 调整 2周→3周】

```
Week 14-16:
├── 全流程联调 + 数据校准
├── JUnit + TestContainers 测试补齐（核心流程必测）
├── 操作日志 + 审计功能
├── 安全加固（XSS过滤/文件类型校验/IP限流/密码BCrypt确认）
├── 数据导出（订单/库存/生产/成本/评分/司机绩效 Excel 导出）
├── 性能优化 + 索引补齐
├── 数据库备份脚本（MySQL dump + MinIO 同步）
├── 部署文档 + 运维脚本 + docker-compose.yml
├── 历史数据迁移脚本（+测试环境验证2次）
└── 用户培训
```

**交付物**：可投产使用的完整系统

> **v1.3 路线图原则**：阶段一+阶段二跑通 = 系统可独立交付（底线6周）。
> 后续阶段是锦上添花。总工期 **16 周**，加缓冲 **18 周**更安全。

---

## 10. 风险评估与对策

| 风险 | 概率 | 影响 | 对策 |
|------|------|------|------|
| AI 评分不准，用户不信任 | 高 | 中 | 初期"建议"定位，人工可覆盖；每项评分注明计算依据；设置"反馈"按钮收集修正 |
| 排产算法不符合实际 | 中 | 高 | 算法支持手动拖拽调整；排产结果标注"建议"，需人工确认；留出手动干预入口 |
| 数据量不足导致评分失真 | 高 | 中 | 少于N条记录时标注"数据不足，仅供参考"；初期用规则引擎兜底 |
| LLM 接口不稳定/费用高 | 中 | 低 | 自然语言查询为附加功能；核心评分用本地算法，不依赖 LLM |
| 单人开发进度延迟 | 中 | 高 | 阶段化交付，每阶段均可独立使用；先做核心流程再做智能功能 |
| BOM 数据录入工作量大 | 中 | 中 | 提供 BOM 复制+微调功能；Excel 批量导入；同类面料一键复用 |
| 成本数据采集不完整 | 中 | 中 | 默认值兜底（如制造费用按产线日费率均摊）；实际数据到位后逐步替换 |
| 历史数据迁移失败 | 低 | 高 | 先出迁移脚本，在测试环境验证两次再上线；保留原始 Excel 备份 |
| AI 服务不可用 | 中 | 中 | Resilience4j 熔断降级；评分返回缓存数据；核心预警用规则引擎兜底 【v1.3新增】 |
| 单机部署数据丢失 | 低 | 高 | MySQL 定时 dump + MinIO 文件同步到另一台机器；数据库备份脚本纳入运维 【v1.3新增】 |
| 开发进度严重延迟 | 中 | 高 | 前 6 周跑通阶段一+阶段二即可独立交付；后续阶段逐块叠加，不阻塞主流程 【v1.3更新】 |

---

## 11. 部署方案 【v1.1 新增】

### 11.1 最低部署配置

```
┌──────────────────────────────────────────┐
│          单台服务器 (4C8G 起步)            │
│                                           │
│  Nginx (80/443)                           │
│    ├── /api/* → localhost:8080 (Spring)   │
│    ├── /ai/*  → localhost:8000 (FastAPI)  │
│    └── /      → Vue 静态文件              │
│                                           │
│  Spring Boot (8080)                       │
│  Python AI  (8000, uvicorn)               │
│  MySQL      (3306)                        │
│  Redis      (6379)                        │
│  MinIO      (9000)                        │
│                                           │
│  事件总线：Redis Stream（替代 RabbitMQ）    │
│  【v1.5修正：单机4C8G跑RabbitMQ偏重，     │
│   改用已有Redis的Stream功能，零额外资源】  │
└──────────────────────────────────────────┘
```

### 11.2 部署选项

| 方案 | 适用场景 | 说明 |
|------|----------|------|
| **Windows 裸机** | 工厂内网使用 | 打包成 Windows 服务，无需 Docker；适合已有 PC 服务器 |
| **Docker Compose** | 有 Docker 环境 | 一键启动所有服务，迁移方便 |
| **Linux 服务器** | 有运维能力 | 推荐，稳定性好，资源占用低 |

### 11.3 首次启动清单

```
1. MySQL 建库 + 执行 init.sql（建表 + 基础数据字典）
2. MinIO 创建 bucket: tex-erp-files
3. Redis Stream 创建消费者组（XGROUP CREATE）
4. 配置 application.yml（数据库连接、AI服务地址、JWT密钥）
5. 配置 AI 服务 .env（LLM API Key、双数据库连接、AI_INTERNAL_KEY） 【v1.5修正】
6. 启动 Spring Boot → 启动 Python AI → 部署前端静态文件
7. 创建管理员账户（admin/admin123，首次登录强制改密） → 录入基础数据 → 开用
```

### 11.4 多单位换算 【v1.1 补充】

纺织行业核心痛点之一：同一个物料不同环节用不同单位。

```
物料单位换算表 (t_unit_conversion):
  纱线: 1吨 = 1000kg, 1箱通常25kg
  面料: 1kg → 米数 = 1000 / (克重 × 门幅) 
        例: 180g/m², 门幅1.8m → 每kg = 1000/(180×1.8) ≈ 3.09m
  卷装: 1卷通常25kg或50kg（可配置）

系统做法：
- 库存主单位: kg（所有内部计算统一用 kg）
- 显示单位: 按场景自动转换（采购看吨/箱，仓库看kg/卷，销售看米）
- 转换系数: t_material 表存储转换公式
```

### 11.5 柬埔寨部署考量 【v1.5 新增】

> 当前在柬埔寨为当地同事部署系统，需考虑跨国环境差异。

| 维度 | 考量 | 方案 |
|------|------|------|
| **时区** | 柬埔寨 UTC+7，中国 UTC+8 | 数据库存 UTC，应用层 `application.yml` 配 `spring.jackson.time-zone=Asia/Shanghai`；若柬方独立运营则配 `Asia/Phnom_Penh`。日期字段（delivery_date 等）在 API 层统一转换 |
| **多币种** | 柬埔寨用 USD/KHR，国内用 CNY | 金额字段增加 `currency`（已加到 t_order）；汇率表 `t_exchange_rate` 手动维护，成本/对账按币种分别统计 |
| **网络** | 柬埔寨→国内 LLM API 延迟和稳定性 | 考虑本地 embedding 模型作为 fallback；LLM 查询增加超时 30s + 降级提示；核心评分不依赖 LLM |
| **语言** | 柬埔寨同事可能需要高棉语 | v1 仅中文，前端 i18n 预留接口（`vue-i18n`），后续按需加高棉语包 |
| **数据合规** | 柬埔寨当地数据驻留要求 | 目前单机本地部署，数据不出境；如需回传国内，需确认合规要求 |
| **离线容灾** | 柬埔寨网络不稳定 | 核心业务（下单/入库/排产）不依赖外网；AI 功能降级后仍可正常运营 |

---

## 12. 遗漏项自查记录 【v1.5 更新】

**v1.5 新增（文档评审修订）：**

| # | 遗漏项 | 影响 | 版本 |
|---|--------|------|------|
| 35 | **Token 存储方案矛盾** | 三处描述不一致，开发踩坑 | v1.5 §3.4.2/3.4.7 |
| 36 | **角色存储冗余** | t_user.roles + t_user_role 并存 | v1.5 §3.4.5/§7.2 |
| 37 | **AI 服务读写权限矛盾** | 只读连接写不了评分表 | v1.5 §3.2/§5.7.2 |
| 38 | **Java 版本不符** | 文档17 vs 实际21 | v1.5 §3.1 |
| 39 | **并发控制缺失** | 库存超卖/订单状态竞争 | v1.5 §6.5 |
| 40 | **评分表无历史版本** | 趋势分析无数据 | v1.5 §7.2 |
| 41 | **软删除/审计字段缺失** | 数据误删不可恢复/责任无法追溯 | v1.5 §6.5/§7.2 |
| 42 | **QC schema 不完整** | 无法覆盖布尔/枚举判定 | v1.5 §7.2 |
| 43 | **RabbitMQ 单机过重** | 4C8G 资源紧张 | v1.5 §11.1 |
| 44 | **AI 服务间无认证** | 内网未授权调用风险 | v1.5 §5.7.1 |
| 45 | **全局异常处理缺失** | 错误响应不统一 | v1.5 §3.7 |
| 46 | **缓存策略缺失** | 无缓存使用规范 | v1.5 §3.8 |
| 47 | **日志规范缺失** | 无系统日志标准 | v1.5 §3.9 |
| 48 | **性能 SLA 缺失** | 无法判断性能是否达标 | v1.5 §3.10 |
| 49 | **接口幂等性缺失** | 网络重试导致重复数据 | v1.5 §3.11 |
| 50 | **种子数据缺失** | 首次部署无初始数据 | v1.5 §3.12 |
| 51 | **柬埔寨部署考量缺失** | 时区/币种/网络/语言未规划 | v1.5 §11.5 |
| 52 | **金额字段冗余** | t_order_cost.order_amount 重复 | v1.5 §7.2 |

**v1.4 新增：**

| # | 遗漏项 | 影响 | 版本 |
|---|--------|------|------|
| 33 | **JWT 详细设计** | 核心类设计、安全策略、前端对接规范、异常处理、配置项补齐 | v1.4 §3.4 |
| 34 | **DB 用户相关表** | 补充 t_user / t_role / t_user_role 建表 SQL | v1.4 §7.2 |

本版本（v1.3）相对于 v1.2 新增/修正的内容：

| # | 遗漏项 | 影响 | 版本 |
|---|--------|------|------|
| 1 | **BOM 与配方管理** | 无 BOM 采购需求无法自动计算 | v1.1 §4.6 |
| 2 | **成本核算** | 评分模型依赖的成本/利润数据无来源 | v1.1 §4.7 |
| 3 | **外发加工** | 产能超载时无解决方案 | v1.1 §4.8 |
| 4 | **QC 标准模板** | 质检无法自动化判定合格/不合格 | v1.1 §4.9 |
| 5 | **工作台与仪表盘** | 用户缺乏入口视角 | v1.1 §4.10 |
| 6 | **消息通知中心** | 自动化动作无人知晓 | v1.1 §4.11 |
| 7 | **数据导入导出** | 历史数据迁移、报表输出无方案 | v1.1 §4.12 |
| 8 | **订单状态机缺异常路径** | 取消/暂停/退回无法处理 | v1.1 §6.1 |
| 9 | **订单变更管理** | 客户改单后下游数据不同步 | v1.1 §6.3 |
| 10 | **部署方案** | 不知道怎么跑起来 | v1.1 §11 |
| 11 | **多单位换算** | kg/米/卷换算没有规范 | v1.1 §11.4 |
| 12 | **数据库遗漏 8 张表** | BOM/成本/QC/通知/外发/变更 | v1.1 §7.2 |
| 13 | **API 遗漏 6 组接口** | BOM/成本/QC/外发/通知/工作台 | v1.1 §8.2 |
| 14 | **风险评估不完整** | BOM录入/成本采集/数据迁移风险 | v1.1 §10 |
| 15 | **样品/确样管理** | 没确样就进大货=找死 | v1.2 §4.13 |
| 16 | **色卡/Lab Dip 管理** | 纺织厂不管理颜色=盲人开车 | v1.2 §4.14 |
| 17 | **裁床管理** | 你每天的裁床天数计算没进系统 | v1.2 §4.15 |
| 18 | **计件工资** | 成本核算缺人工成本 | v1.2 §4.16 |
| 19 | **批号/缸号追溯** | 质量投诉无法追溯到批次 | v1.2 §4.17 |
| 20 | **对账单管理** | AI评分缺应收应付数据 | v1.2 §4.18 |
| 21 | **司机绩效考核** | 你每月手动从WPS拉数据做的活 | v1.2 §4.19 |
| 22 | **认证方案缺失** | 阶段一第一个Controller都写不了 | v1.3 §3.4 |
| 23 | **数据库迁移方案** | 20+张表无版本管理=生产事故 | v1.3 §3.5 |
| 24 | **收付款记录表** | 客户评分"付款及时率"无数据来源 | v1.3 §7.2 t_payment |
| 25 | **批次追溯关联表** | 字段方案无法支持多对多追溯 | v1.3 §7.2 t_batch_trace |
| 26 | **AI服务降级方案** | Python AI 挂了主系统跟着挂 | v1.3 §5.7 |
| 27 | **MinIO文件API** | 有存储无上传/下载接口 | v1.3 §8 文件管理 |
| 28 | **产线工作日历** | 排产不考虑节假日/检修日 | v1.3 §7.2 t_line_calendar |
| 29 | **测试策略缺失** | 一人开发不写测试=改一个崩三个 | v1.3 §3.6 |
| 30 | **t_order缺关键字段** | KPI计算缺order_amount/confirmed_at/completed_at | v1.3 §7.2 |
| 31 | **批量操作API缺失** | ERP日常操作无批量=点死人 | v1.3 §8 批量操作 |
| 32 | **BOM缺copied_from** | 复制后无法溯源 | v1.3 §7.2 t_bom |

**已知但暂不纳入 v1 的项**（记下来避免忘）：
- 移动端适配（后续做 PWA 或小程序）
- 设备物联网对接（织机/染缸数据采集，预留接口）
- 多语言支持（目前仅中文）
- 扫码枪硬件集成（仓库用，USB HID 模式，无需额外开发）
- 自动排产的多目标优化（目前贪心，后续可改遗传算法）
- 色差管理 ΔE（高端客户色差标准，可并入 QC 标准模块，v2 迭代）
- 客户授信额度（下单自动控额，v2 迭代）
- 扫码报工 H5（工人手机扫码报产量，v2 迭代）
- t_bom.fabric_type 改为外键 ID（当前 VARCHAR 做唯一键不够稳，v2 迭代） 【v1.3 已知】
- SpringDoc 全局异常响应体标准化 【v1.3 已知 → v1.5 已解决，见 §3.7】

---

## 附录 A：与现有系统的关系

| 现有系统 | 与新ERP关系 |
|----------|------------|
| 排程系统（Spring Boot，准备开源） | 排产算法可复用，但需改造为支持多产线+面料匹配 |
| QC 数据管理系统（Python + SQLite） | 质检模块可吸收合并，数据迁移到 MySQL |
| VisionAgent（桌面自动化） | 后续可配合做扫码入库、标签识别 |
| WPS 二次开发 | 报表导出可复用 WPS 模板生成逻辑 |

---

## 附录 B：推荐 LLM 选型

| 模型 | 用途 | 优势 |
|------|------|------|
| DeepSeek-V3 | 自然语言查询（主力） | 性价比极高，中文理解好，API 稳定 |
| Qwen-Max | 分析报告生成 | 长文本理解强，结构化输出好 |
| 本地 embedding 模型 | 语义相似度（客户投诉归类等） | 零成本，隐私安全 |

---

> **文档状态**：v1.5，已完成文档评审修订（30项问题修复），可进入开发
> **下一步**：确认技术选型 → 搭建项目骨架 → 进入阶段一开发

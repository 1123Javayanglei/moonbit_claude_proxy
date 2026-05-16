# MoonBit Claude Code Proxy

一个用 MoonBit 实现的代理服务器，将 Claude API 请求转换为 OpenAI API 调用，使 Claude Code 能够与任何 OpenAI 兼容的 API 提供商协同工作。

## 项目结构

```
moonbit_claude_proxy/
├── moon.mod.json              # 模块配置 (依赖 moonbitlang/async 0.19.0)
├── moon.pkg                   # 根包导入配置
├── constants.mbt              # API 常量定义 (角色、内容类型、SSE 事件等)
├── config.mbt                 # 环境变量配置管理
├── model_manager.mbt          # Claude → OpenAI 模型映射
├── models.mbt                 # 数据模型 (Claude/OpenAI API 类型及 JSON 解析)
├── request_converter.mbt      # Claude → OpenAI 请求格式转换
├── response_converter.mbt     # OpenAI → Claude 响应转换 + SSE 流式处理
├── openai_client.mbt          # 异步 HTTP 客户端 (OpenAI API 调用)
├── server.mbt                 # HTTP 服务器 (路由、端点、请求处理)
└── cmd/main/
    ├── moon.pkg               # 可执行包配置 (native 目标)
    └── main.mbt               # 入口点
```

## 功能特性

- **Claude API 兼容:** 支持 `/v1/messages`、`/v1/messages/count_tokens`、`/health`、`/test-connection` 端点
- **多提供商支持:** OpenAI、Azure OpenAI、Ollama 以及任何 OpenAI 兼容 API (通过 `OPENAI_BASE_URL` 配置)
- **模型映射:** haiku → SMALL_MODEL, sonnet → MIDDLE_MODEL, opus → BIG_MODEL
- **函数调用:** 完整的 tool_use / tool_result 在 Claude 和 OpenAI 格式之间转换
- **流式响应:** SSE 实时流式响应转换，包含完整的事件序列
- **图像支持:** Base64 图像从 Claude 格式转换为 OpenAI 格式
- **API 密钥验证:** 通过 `ANTHROPIC_API_KEY` 可选的客户端密钥校验
- **自定义 HTTP 头:** 通过 `CUSTOM_HEADER_*` 环境变量注入自定义请求头

## 环境配置

### 必需变量

| 环境变量 | 说明 |
|---------|------|
| `OPENAI_API_KEY` | OpenAI API 密钥 |

### 模型配置

| 环境变量 | 说明 | 默认值 |
|---------|------|---------|
| `BIG_MODEL` | opus 请求使用的模型 | `gpt-4o` |
| `MIDDLE_MODEL` | sonnet 请求使用的模型 | 同 BIG_MODEL |
| `SMALL_MODEL` | haiku 请求使用的模型 | `gpt-4o-mini` |

### API 配置

| 环境变量 | 说明 | 默认值 |
|---------|------|---------|
| `OPENAI_BASE_URL` | API 基础 URL | `https://api.openai.com/v1` |
| `ANTHROPIC_API_KEY` | 客户端验证密钥 (可选) | 未设置 |
| `HOST` | 服务器主机 | `0.0.0.0` |
| `PORT` | 服务器端口 | `8082` |

### 性能配置

| 环境变量 | 说明 | 默认值 |
|---------|------|---------|
| `MAX_TOKENS_LIMIT` | 最大 tokens 限制 | `4096` |
| `MIN_TOKENS_LIMIT` | 最小 tokens 限制 | `100` |
| `REQUEST_TIMEOUT` | 请求超时 (秒) | `90` |

## 快速开始

### 1. 安装 MoonBit

```bash
curl -fsSL https://cli.moonbitlang.com/install.sh | bash
```

### 2. 配置环境

```bash
export OPENAI_API_KEY="sk-your-api-key"
export BIG_MODEL="gpt-4o"
export SMALL_MODEL="gpt-4o-mini"
```

### 3. 启动服务器

```bash
cd moonbit_claude_proxy
moon run cmd/main
```

### 4. 与 Claude Code 集成

```bash
ANTHROPIC_BASE_URL=http://localhost:8082 claude
```

## 模型映射规则

| Claude 模型 | 映射到 | 环境变量 |
|-----------|--------|---------|
| 包含 "haiku" | `SMALL_MODEL` | 默认: `gpt-4o-mini` |
| 包含 "sonnet" | `MIDDLE_MODEL` | 默认: `gpt-4o` |
| 包含 "opus" | `BIG_MODEL` | 默认: `gpt-4o` |

如果模型名称包含 `gpt-`、`o1-`、`ep-`、`doubao-` 或 `deepseek-` 前缀，则直接透传，不做映射。

## 提供商配置示例

### OpenAI

```bash
export OPENAI_API_KEY="sk-your-openai-key"
export OPENAI_BASE_URL="https://api.openai.com/v1"
export BIG_MODEL="gpt-4o"
export SMALL_MODEL="gpt-4o-mini"
```

### Azure OpenAI

```bash
export OPENAI_API_KEY="your-azure-key"
export OPENAI_BASE_URL="https://your-resource.openai.azure.com/openai/deployments/your-deployment"
export BIG_MODEL="gpt-4"
export SMALL_MODEL="gpt-35-turbo"
```

### Ollama (本地模型)

```bash
export OPENAI_API_KEY="dummy-key"
export OPENAI_BASE_URL="http://localhost:11434/v1"
export BIG_MODEL="llama3.1:70b"
export SMALL_MODEL="llama3.1:8b"
```

## 请求/响应流程

```
Claude Code 客户端
        ↓
    [HTTP 请求]
        ↓
  API 端点验证 (可选密钥校验)
        ↓
  请求转换器 (Claude → OpenAI 格式)
        ↓
  模型映射 (根据模型名称选择目标)
        ↓
  OpenAI HTTP 客户端 (异步)
        ↓
   OpenAI API 服务器
        ↓
  响应转换器 (OpenAI → Claude 格式)
        ↓
  [HTTP 响应 / SSE 流]
        ↓
Claude Code 客户端
```

## 技术栈

- **语言:** MoonBit
- **异步运行时:** moonbitlang/async 0.19.0
- **HTTP 服务器/客户端:** moonbitlang/async/http
- **JSON 处理:** moonbitlang/core/json
- **目标平台:** native

## 开发

```bash
# 类型检查
moon check --target native

# 格式化代码
moon fmt

# 运行
moon run cmd/main

# 查看帮助
moon run cmd/main -- --help
```

## 许可证

MIT License

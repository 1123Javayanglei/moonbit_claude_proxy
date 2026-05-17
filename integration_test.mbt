///|
/// 集成测试：加载 .env，真实发送请求，打印请求/响应。
/// 运行: `moon test --target native integration_test.mbt`

///|
/// 加载 .env 配置
async fn load_test_config() -> Config {
  load_env() catch { _ => () }
  Config::load()
}

///|
/// 打印分隔线
fn print_section(title : String) -> Unit {
  println("")
  println("══════════════════════════════════════════════════")
  println("  \{title}")
  println("══════════════════════════════════════════════════")
}

///|
/// 打印 JSON（带缩进，用 stringify）
fn print_json(label : String, json : Json) -> Unit {
  println("")
  println("── \{label} ──")
  println(json.stringify())
}

///|
async test "integration_simple_chat" {
  print_section("测试 1：简单对话")
  let config = load_test_config()

  let claude_req = ClaudeMessagesRequest::from_json(
    Json::object({
      "model": Json::string("claude-sonnet-4-20250514"),
      "max_tokens": Json::number(200.0),
      "messages": Json::array([
        Json::object({
          "role": Json::string("user"),
          "content": Json::string("你好，请用一句话介绍你自己。"),
        }),
      ]),
      "stream": Json::boolean(false),
    }),
  ).unwrap()

  let openai_req = convert_claude_to_openai(claude_req, config)
  print_json("OpenAI 请求", Json::object(openai_req))

  let client = OpenAIClient::new(config)
  let openai_resp = client.chat_completion(openai_req)
  print_json("OpenAI 响应", Json::object(openai_resp))

  match openai_resp.get("error") {
    Some(err) => abort("API 错误: \{err.stringify()}")
    None => ()
  }

  let claude_resp = convert_openai_to_claude_response(openai_resp, "claude-sonnet-4-20250514")
  print_json("Claude 格式响应", Json::object(claude_resp))

  // 验证基本结构
  match claude_resp.get("type") {
    Some(Json::String(t)) => inspect(t, content="message")
    _ => abort("missing type")
  }
  println("")
  println("✅ 简单对话测试通过")
}

///|
async test "integration_with_system_prompt" {
  print_section("测试 2：带 System Prompt")
  let config = load_test_config()

  let claude_req = ClaudeMessagesRequest::from_json(
    Json::object({
      "model": Json::string("claude-haiku-3-5-20241022"),
      "max_tokens": Json::number(150.0),
      "system": Json::string("你是一个中国古代诗人，请用七言绝句的风格回答问题。"),
      "messages": Json::array([
        Json::object({
          "role": Json::string("user"),
          "content": Json::string("描写一下春天"),
        }),
      ]),
      "stream": Json::boolean(false),
    }),
  ).unwrap()

  let openai_req = convert_claude_to_openai(claude_req, config)
  print_json("OpenAI 请求（含 system）", Json::object(openai_req))

  let client = OpenAIClient::new(config)
  let openai_resp = client.chat_completion(openai_req)
  print_json("OpenAI 响应", Json::object(openai_resp))

  match openai_resp.get("error") {
    Some(err) => abort("API 错误: \{err.stringify()}")
    None => ()
  }

  let claude_resp = convert_openai_to_claude_response(openai_resp, "claude-haiku-3-5-20241022")
  print_json("Claude 格式响应", Json::object(claude_resp))

  match claude_resp.get("content") {
    Some(Json::Array(blocks)) if blocks.length() > 0 => {
      inspect(blocks.length() >= 1, content="true")
    }
    _ => abort("missing content")
  }
  println("")
  println("✅ System Prompt 测试通过")
}

///|
async test "integration_tool_calling" {
  print_section("测试 3：工具调用")
  let config = load_test_config()

  let claude_req = ClaudeMessagesRequest::from_json(
    Json::object({
      "model": Json::string("claude-sonnet-4-20250514"),
      "max_tokens": Json::number(300.0),
      "tools": Json::array([
        Json::object({
          "name": Json::string("get_weather"),
          "description": Json::string("Get current weather information for a city"),
          "input_schema": Json::object({
            "type": Json::string("object"),
            "properties": Json::object({
              "city": Json::object({
                "type": Json::string("string"),
                "description": Json::string("City name"),
              }),
              "unit": Json::object({
                "type": Json::string("string"),
                "enum": Json::array([
                  Json::string("celsius"),
                  Json::string("fahrenheit"),
                ]),
              }),
            }),
            "required": Json::array([Json::string("city")]),
          }),
        }),
        Json::object({
          "name": Json::string("calculate"),
          "description": Json::string("Perform a mathematical calculation"),
          "input_schema": Json::object({
            "type": Json::string("object"),
            "properties": Json::object({
              "expression": Json::object({
                "type": Json::string("string"),
                "description": Json::string("Math expression to evaluate"),
              }),
            }),
            "required": Json::array([Json::string("expression")]),
          }),
        }),
      ]),
      "messages": Json::array([
        Json::object({
          "role": Json::string("user"),
          "content": Json::string("北京的天气怎么样？另外帮我算一下 123 * 456"),
        }),
      ]),
      "stream": Json::boolean(false),
    }),
  ).unwrap()

  let openai_req = convert_claude_to_openai(claude_req, config)
  print_json("OpenAI 请求（含 tools）", Json::object(openai_req))

  let client = OpenAIClient::new(config)
  let openai_resp = client.chat_completion(openai_req)
  print_json("OpenAI 响应", Json::object(openai_resp))

  match openai_resp.get("error") {
    Some(err) => abort("API 错误: \{err.stringify()}")
    None => ()
  }

  let claude_resp = convert_openai_to_claude_response(openai_resp, "claude-sonnet-4-20250514")
  print_json("Claude 格式响应", Json::object(claude_resp))

  // 验证 stop_reason 或 tool_use
  match claude_resp.get("stop_reason") {
    Some(s) => {
      let reason = s.stringify()
      inspect(reason.contains("tool") || reason.contains("end_turn"), content="true")
    }
    _ => abort("missing stop_reason")
  }
  println("")
  println("✅ 工具调用测试通过")
}

///|
async test "integration_model_mapping" {
  print_section("测试 4：模型映射验证")
  let config = load_test_config()

  let claude_models = [
    "claude-haiku-3-5-20241022",
    "claude-sonnet-4-20250514",
    "claude-opus-4-20250514",
  ]
  let expected_models = [
    config.small_model,
    config.middle_model,
    config.big_model,
  ]

  for i in 0..<claude_models.length() {
    let claude_model = claude_models[i]
    let expected_openai = expected_models[i]
    let result = map_claude_model_to_openai(claude_model, config)
    println("  映射: \{claude_model} → \{result}")
    inspect(result, content=expected_openai)
  }
  println("")
  println("✅ 模型映射验证通过")
}

///|
async test "integration_health_and_root" {
  print_section("测试 5：配置摘要")
  let config = load_test_config()

  println("  Base URL : \{config.openai_base_url}")
  println("  Big      : \{config.big_model}")
  println("  Middle   : \{config.middle_model}")
  println("  Small    : \{config.small_model}")
  println("  Timeout  : \{config.request_timeout}s")
  println("  Tokens   : max=\{config.max_tokens_limit}, min=\{config.min_tokens_limit}")
  println("  Server   : \{config.host}:\{config.port}")
  let has_auth = config.anthropic_api_key is Some(_)
  let auth_status = if has_auth { "enabled" } else { "disabled" }
  println("  Auth     : \{auth_status}")
  println("")
  println("✅ 配置摘要通过")
}

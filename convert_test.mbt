///|
/// 单元测试：请求/响应转换、模型映射、SSE 事件。
/// 运行: `moon test --target native`

///|
/// 构造最小 Config 用于测试
fn test_config() -> Config {
  Config::load() catch {
    _ => {
      {
        openai_api_key: "test-key",
        anthropic_api_key: None,
        openai_base_url: "https://api.openai.com/v1",
        big_model: "gpt-4o",
        middle_model: "gpt-4o",
        small_model: "gpt-4o-mini",
        host: "0.0.0.0",
        port: 8082,
        max_tokens_limit: 4096,
        min_tokens_limit: 100,
        request_timeout: 90,
      }
    }
  }
}

///|
/// 构造一个简单的 Claude text message 请求 JSON，然后测试转换
fn make_simple_claude_json() -> Json {
  Json::object({
    "model": Json::string("claude-sonnet-4-20250514"),
    "max_tokens": Json::number(1024.0),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("Hello, how are you?"),
      }),
    ]),
    "stream": Json::boolean(false),
  })
}

///|
/// 构造带 system prompt 的 Claude 请求
fn make_system_claude_json() -> Json {
  Json::object({
    "model": Json::string("claude-opus-4-20250514"),
    "max_tokens": Json::number(2048.0),
    "system": Json::string("You are a helpful assistant."),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("Hello"),
      }),
    ]),
    "stream": Json::boolean(false),
  })
}

///|
/// 构造带 tool use 的 Claude 请求
fn make_tool_claude_json() -> Json {
  Json::object({
    "model": Json::string("claude-sonnet-4-20250514"),
    "max_tokens": Json::number(1024.0),
    "tools": Json::array([
      Json::object({
        "name": Json::string("get_weather"),
        "description": Json::string("Get current weather for a location"),
        "input_schema": Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "location": Json::object({
              "type": Json::string("string"),
            }),
          }),
          "required": Json::array([Json::string("location")]),
        }),
      }),
    ]),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("What's the weather in Beijing?"),
      }),
    ]),
    "stream": Json::boolean(false),
  })
}

///|
/// 构造 OpenAI 文本响应 JSON
fn make_openai_response_json() -> Json {
  Json::object({
    "id": Json::string("chatcmpl-123"),
    "choices": Json::array([
      Json::object({
        "finish_reason": Json::string("stop"),
        "message": Json::object({
          "role": Json::string("assistant"),
          "content": Json::string("Hello! I'm doing well, thank you."),
        }),
      }),
    ]),
    "usage": Json::object({
      "prompt_tokens": Json::number(10.0),
      "completion_tokens": Json::number(8.0),
    }),
  })
}

///|
/// 构造 OpenAI tool call 响应 JSON
fn make_openai_tool_response_json() -> Json {
  Json::object({
    "id": Json::string("chatcmpl-456"),
    "choices": Json::array([
      Json::object({
        "finish_reason": Json::string("tool_calls"),
        "message": Json::object({
          "role": Json::string("assistant"),
          "content": Json::null(),
          "tool_calls": Json::array([
            Json::object({
              "id": Json::string("call_abc123"),
              "type": Json::string("function"),
              "function": Json::object({
                "name": Json::string("get_weather"),
                "arguments": Json::string("{\"location\":\"Beijing\"}"),
              }),
            }),
          ]),
        }),
      }),
    ]),
    "usage": Json::object({
      "prompt_tokens": Json::number(20.0),
      "completion_tokens": Json::number(15.0),
    }),
  })
}

///|
test "model_manager_basic" {
  let c = test_config()
  inspect(map_claude_model_to_openai("claude-haiku-3-5-20241022", c), content="gpt-4o-mini")
  inspect(map_claude_model_to_openai("claude-sonnet-4-20250514", c), content="gpt-4o")
  inspect(map_claude_model_to_openai("claude-opus-4-20250514", c), content="gpt-4o")
}

///|
test "model_manager_passthrough" {
  let c = test_config()
  inspect(map_claude_model_to_openai("gpt-4", c), content="gpt-4")
  inspect(map_claude_model_to_openai("o1-mini", c), content="o1-mini")
  inspect(map_claude_model_to_openai("deepseek-chat", c), content="deepseek-chat")
}

///|
test "convert_simple_text_message" {
  let c = test_config()
  let json = make_simple_claude_json()
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  // 模型映射
  inspect(result.get("model"), content=(
    #|Some(String(gpt-4o))
  ))

  // messages 数量
  match result.get("messages") {
    Some(Json::Array(arr)) => inspect(arr.length(), content="1")
    _ => abort("missing messages")
  }

  // max_tokens
  inspect(result.get("max_tokens"), content=(
    #|Some(Number(1024))
  ))

  // stream
  inspect(result.get("stream"), content=(
    #|Some(False)
  ))
}

///|
test "convert_system_message" {
  let c = test_config()
  let json = make_system_claude_json()
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  // opus → big_model
  inspect(result.get("model"), content=(
    #|Some(String(gpt-4o))
  ))

  match result.get("messages") {
    Some(Json::Array(arr)) => {
      inspect(arr.length(), content="2")
      // 第一条是 system
      match arr[0] {
        Json::Object(m) => inspect(m.get("role"), content=(
          #|Some(String(system))
        ))
        _ => abort("expected object")
      }
    }
    _ => abort("missing messages")
  }

  inspect(result.get("max_tokens"), content=(
    #|Some(Number(2048))
  ))
}

///|
test "convert_tool_definitions" {
  let c = test_config()
  let json = make_tool_claude_json()
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  // 验证 tools 被转换
  match result.get("tools") {
    Some(Json::Array(arr)) => {
      inspect(arr.length(), content="1")
      match arr[0] {
        Json::Object(tool) => {
          inspect(tool.get("type"), content=(
            #|Some(String(function))
          ))
          match tool.get("function") {
            Some(Json::Object(fn_obj)) => {
              inspect(fn_obj.get("name"), content=(
                #|Some(String(get_weather))
              ))
            }
            _ => abort("expected function obj")
          }
        }
        _ => abort("expected object")
      }
    }
    _ => abort("expected tools")
  }
}

///|
test "convert_response_text" {
  let json = make_openai_response_json()
  match json {
    Json::Object(obj) => {
      let result = convert_openai_to_claude_response(obj, "claude-sonnet-4-20250514")
      inspect(result.get("type"), content=(
        #|Some(String(message))
      ))
      inspect(result.get("role"), content=(
        #|Some(String(assistant))
      ))
      inspect(result.get("model"), content=(
        #|Some(String(claude-sonnet-4-20250514))
      ))
      inspect(result.get("stop_reason"), content=(
        #|Some(String(end_turn))
      ))

      match result.get("content") {
        Some(Json::Array(blocks)) => {
          inspect(blocks.length(), content="1")
          match blocks[0] {
            Json::Object(block) => {
              inspect(block.get("type"), content=(
                #|Some(String(text))
              ))
            }
            _ => abort("expected block")
          }
        }
        _ => abort("expected content array")
      }
    }
    _ => abort("expected object")
  }
}

///|
test "convert_response_tool_use" {
  let json = make_openai_tool_response_json()
  match json {
    Json::Object(obj) => {
      let result = convert_openai_to_claude_response(obj, "claude-sonnet-4-20250514")
      inspect(result.get("stop_reason"), content=(
        #|Some(String(tool_use))
      ))

      match result.get("content") {
        Some(Json::Array(blocks)) => {
          inspect(blocks.length(), content="1")
          match blocks[0] {
            Json::Object(block) => {
              inspect(block.get("type"), content=(
                #|Some(String(tool_use))
              ))
              inspect(block.get("name"), content=(
                #|Some(String(get_weather))
              ))
              match block.get("input") {
                Some(Json::Object(input)) => {
                  inspect(input.get("location"), content=(
                    #|Some(String(Beijing))
                  ))
                }
                _ => abort("expected input object")
              }
            }
            _ => abort("expected block")
          }
        }
        _ => abort("expected content array")
      }
    }
    _ => abort("expected object")
  }
}

///|
test "sse_events_format" {
  let start = sse_message_start("msg_001", "claude-sonnet")
  inspect(start.has_prefix("event: message_start"), content="true")
  inspect(start.contains("msg_001"), content="true")

  let delta = sse_text_delta(0, "Hello")
  inspect(delta.has_prefix("event: content_block_delta"), content="true")
  inspect(delta.contains("Hello"), content="true")

  let stop = sse_content_block_stop(0)
  inspect(stop.has_prefix("event: content_block_stop"), content="true")

  let msg_stop = sse_message_stop()
  inspect(msg_stop.has_prefix("event: message_stop"), content="true")

  let err = sse_error("test error")
  inspect(err.contains("test error"), content="true")
}

///|
test "parse_claude_request_json" {
  let json = make_simple_claude_json()
  let req = ClaudeMessagesRequest::from_json(json)
  match req {
    Some(r) => {
      inspect(r.model, content="claude-sonnet-4-20250514")
      inspect(r.max_tokens, content="1024")
      inspect(r.stream, content="false")
      inspect(r.messages.length(), content="1")
    }
    None => abort("failed to parse")
  }
}

///|
test "parse_system_request" {
  let json = make_system_claude_json()
  let req = ClaudeMessagesRequest::from_json(json)
  match req {
    Some(r) => {
      inspect(r.model, content="claude-opus-4-20250514")
      match r.system {
        Some(Json::String(s)) => inspect(s.contains("helpful"), content="true")
        _ => abort("expected system string")
      }
    }
    None => abort("failed to parse")
  }
}

///|
test "parse_tool_request" {
  let json = make_tool_claude_json()
  let req = ClaudeMessagesRequest::from_json(json)
  match req {
    Some(r) => {
      inspect(r.tools.length(), content="1")
      inspect(r.tools[0].name, content="get_weather")
    }
    None => abort("failed to parse")
  }
}

///|
test "claude_content_block_parse_text" {
  let json = Json::object({
    "type": Json::string("text"),
    "text": Json::string("Hello world"),
  })
  let block = ClaudeContentBlock::from_json(json)
  match block {
    Some(TextBlock(t)) => inspect(t, content="Hello world")
    _ => abort("expected TextBlock")
  }
}

///|
test "claude_content_block_parse_tool_use" {
  let json = Json::object({
    "type": Json::string("tool_use"),
    "id": Json::string("tool_001"),
    "name": Json::string("read_file"),
    "input": Json::object({
      "path": Json::string("/tmp/test.txt"),
    }),
  })
  let block = ClaudeContentBlock::from_json(json)
  match block {
    Some(ToolUseBlock(id, name, input)) => {
      inspect(id, content="tool_001")
      inspect(name, content="read_file")
      inspect(input.get("path"), content=(
        #|Some(String(/tmp/test.txt))
      ))
    }
    _ => abort("expected ToolUseBlock")
  }
}

///|
test "convert_with_temperature_and_top_p" {
  let c = test_config()
  let json = Json::object({
    "model": Json::string("claude-haiku-3-5-20241022"),
    "max_tokens": Json::number(512.0),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("Hi"),
      }),
    ]),
    "temperature": Json::number(0.7),
    "top_p": Json::number(0.9),
    "stream": Json::boolean(false),
  })
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  inspect(result.get("temperature"), content=(
    #|Some(Number(0.7))
  ))
  inspect(result.get("top_p"), content=(
    #|Some(Number(0.9))
  ))
  inspect(result.get("model"), content=(
    #|Some(String(gpt-4o-mini))
  ))
}

///|
test "convert_with_stop_sequences" {
  let c = test_config()
  let json = Json::object({
    "model": Json::string("claude-sonnet-4-20250514"),
    "max_tokens": Json::number(1024.0),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("Hello"),
      }),
    ]),
    "stop_sequences": Json::array([
      Json::string("END"),
      Json::string("STOP"),
    ]),
    "stream": Json::boolean(false),
  })
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  match result.get("stop") {
    Some(Json::Array(arr)) => inspect(arr.length(), content="2")
    _ => abort("expected stop array")
  }
}

///|
test "convert_response_usage" {
  let json = make_openai_response_json()
  match json {
    Json::Object(obj) => {
      let result = convert_openai_to_claude_response(obj, "claude-sonnet")
      match result.get("usage") {
        Some(Json::Object(u)) => {
          inspect(u.get("input_tokens"), content=(
            #|Some(Number(10))
          ))
          inspect(u.get("output_tokens"), content=(
            #|Some(Number(8))
          ))
        }
        _ => abort("expected usage")
      }
    }
    _ => abort("expected object")
  }
}

///|
test "convert_user_message_with_image" {
  let c = test_config()
  let json = Json::object({
    "model": Json::string("claude-sonnet-4-20250514"),
    "max_tokens": Json::number(1024.0),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::array([
          Json::object({
            "type": Json::string("text"),
            "text": Json::string("Describe this image:"),
          }),
          Json::object({
            "type": Json::string("image"),
            "source": Json::object({
              "type": Json::string("base64"),
              "media_type": Json::string("image/png"),
              "data": Json::string("iVBORw0KGgo="),
            }),
          }),
        ]),
      }),
    ]),
    "stream": Json::boolean(false),
  })
  let req = ClaudeMessagesRequest::from_json(json).unwrap()
  let result = convert_claude_to_openai(req, c)

  match result.get("messages") {
    Some(Json::Array(arr)) => {
      match arr[0] {
        Json::Object(msg) => {
          match msg.get("content") {
            Some(Json::Array(parts)) => {
              // 应该有 2 个部分: text + image
              inspect(parts.length(), content="2")
            }
            _ => abort("expected content array")
          }
        }
        _ => abort("expected message object")
      }
    }
    _ => abort("expected messages")
  }
}

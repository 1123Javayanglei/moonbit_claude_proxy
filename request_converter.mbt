///|
/// Convert Claude API requests to OpenAI API format.

///|
pub fn convert_claude_to_openai(
  request : ClaudeMessagesRequest,
  config : Config,
) -> Map[String, Json] {
  let openai_model = map_claude_model_to_openai(request.model, config)

  let openai_messages : Array[Json] = []

  // Add system message if present
  match request.system {
    Some(system) => {
      let system_text = extract_system_text(system)
      if system_text != "" {
        openai_messages.push(
          Json::object({
            "role": Json::string("system"),
            "content": Json::string(system_text),
          }),
        )
      }
    }
    None => ()
  }

  // Process messages with tool result merging
  let mut i = 0
  while i < request.messages.length() {
    let msg = request.messages[i]
    match msg.role {
      "user" => openai_messages.push(convert_user_message(msg))
      "assistant" => {
        openai_messages.push(convert_assistant_message(msg))
        if i + 1 < request.messages.length() {
          let next_msg = request.messages[i + 1]
          if next_msg.role == "user" && has_tool_results(next_msg.content) {
            i += 1
            for tr in convert_tool_results(request.messages[i]) {
              openai_messages.push(tr)
            }
          }
        }
      }
      _ => ()
    }
    i += 1
  }

  // Calculate max_tokens (clamped)
  let max_tokens = if request.max_tokens < config.min_tokens_limit {
    config.min_tokens_limit
  } else if request.max_tokens > config.max_tokens_limit {
    config.max_tokens_limit
  } else {
    request.max_tokens
  }

  // Build OpenAI request
  let openai_request : Map[String, Json] = {}
  openai_request["model"] = Json::string(openai_model)
  openai_request["messages"] = Json::array(openai_messages)
  openai_request["max_tokens"] = Json::number(max_tokens.to_double())
  openai_request["temperature"] = Json::number(request.temperature)
  openai_request["stream"] = if request.stream {
    Json::boolean(true)
  } else {
    Json::boolean(false)
  }

  // Add optional stop sequences
  if request.stop_sequences.length() > 0 {
    let stop_arr : Array[Json] = []
    for s in request.stop_sequences {
      stop_arr.push(Json::string(s))
    }
    openai_request["stop"] = Json::array(stop_arr)
  }

  // Add optional top_p
  match request.top_p {
    Some(top_p) => openai_request["top_p"] = Json::number(top_p)
    None => ()
  }

  // Convert tools
  if request.tools.length() > 0 {
    let openai_tools : Array[Json] = []
    for tool in request.tools {
      if tool.name != "" {
        openai_tools.push(
          Json::object({
            "type": Json::string("function"),
            "function": Json::object({
              "name": Json::string(tool.name),
              "description": match tool.description {
                Some(d) => Json::string(d)
                None => Json::string("")
              },
              "parameters": Json::object(tool.input_schema),
            }),
          }),
        )
      }
    }
    if openai_tools.length() > 0 {
      openai_request["tools"] = Json::array(openai_tools)
    }
  }

  // Convert tool choice
  match request.tool_choice {
    Some(tc) =>
      match tc.get("type") {
        Some(Json::String(choice_type)) =>
          if choice_type == "auto" || choice_type == "any" {
            openai_request["tool_choice"] = Json::string("auto")
          } else if choice_type == "tool" {
            match tc.get("name") {
              Some(name) =>
                openai_request["tool_choice"] = Json::object({
                  "type": Json::string("function"),
                  "function": Json::object({ "name": name }),
                })
              _ => openai_request["tool_choice"] = Json::string("auto")
            }
          } else {
            openai_request["tool_choice"] = Json::string("auto")
          }
        _ => ()
      }
    None => ()
  }

  openai_request
}

///|
fn extract_system_text(system : Json) -> String {
  match system {
    Json::String(s) => s
    Json::Array(arr) => {
      let parts : Array[String] = []
      for block in arr {
        match block {
          Json::Object(obj) =>
            match obj.get("type") {
              Some(Json::String("text")) =>
                match obj.get("text") {
                  Some(Json::String(t)) => parts.push(t)
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      }
      parts.join("\n\n")
    }
    _ => ""
  }
}

///|
fn has_tool_results(content : Json) -> Bool {
  match content {
    Json::Array(arr) => {
      for item in arr {
        match item {
          Json::Object(obj) =>
            match obj.get("type") {
              Some(Json::String("tool_result")) => return true
              _ => ()
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn convert_user_message(msg : ClaudeMessage) -> Json {
  match msg.content {
    Json::String(s) =>
      Json::object({ "role": Json::string("user"), "content": Json::string(s) })
    Json::Array(arr) => {
      let openai_content : Array[Json] = []
      for block in arr {
        match block {
          Json::Object(obj) =>
            match obj.get("type") {
              Some(Json::String("text")) =>
                match obj.get("text") {
                  Some(Json::String(t)) =>
                    openai_content.push(
                      Json::object({
                        "type": Json::string("text"),
                        "text": Json::string(t),
                      }),
                    )
                  _ => ()
                }
              Some(Json::String("image")) =>
                match obj.get("source") {
                  Some(Json::Object(source)) => {
                    let media_type = match source.get("media_type") {
                      Some(Json::String(mt)) => mt
                      _ => ""
                    }
                    let data = match source.get("data") {
                      Some(Json::String(d)) => d
                      _ => ""
                    }
                    if media_type != "" && data != "" {
                      openai_content.push(
                        Json::object({
                          "type": Json::string("image_url"),
                          "image_url": Json::object({
                            "url": Json::string(
                              "data:\{media_type};base64,\{data}",
                            ),
                          }),
                        }),
                      )
                    }
                  }
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      }
      if openai_content.length() == 1 {
        match openai_content[0] {
          Json::Object(o) if o.get("type") == Some(Json::string("text")) => {
            let text = match o.get("text") {
              Some(Json::String(t)) => t
              _ => ""
            }
            Json::object({
              "role": Json::string("user"),
              "content": Json::string(text),
            })
          }
          _ =>
            Json::object({
              "role": Json::string("user"),
              "content": Json::array(openai_content),
            })
        }
      } else {
        Json::object({
          "role": Json::string("user"),
          "content": Json::array(openai_content),
        })
      }
    }
    _ =>
      Json::object({ "role": Json::string("user"), "content": Json::string("") })
  }
}

///|
fn convert_assistant_message(msg : ClaudeMessage) -> Json {
  let text_parts : Array[String] = []
  let tool_calls : Array[Json] = []

  match msg.content {
    Json::String(s) =>
      Json::object({
        "role": Json::string("assistant"),
        "content": Json::string(s),
      })
    Json::Array(arr) => {
      for block in arr {
        match block {
          Json::Object(obj) =>
            match obj.get("type") {
              Some(Json::String("text")) =>
                match obj.get("text") {
                  Some(Json::String(t)) => text_parts.push(t)
                  _ => ()
                }
              Some(Json::String("tool_use")) => {
                let id = match obj.get("id") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
                let name = match obj.get("name") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
                let args = match obj.get("input") {
                  Some(input) => input.stringify()
                  None => "{}"
                }
                tool_calls.push(
                  Json::object({
                    "id": Json::string(id),
                    "type": Json::string("function"),
                    "function": Json::object({
                      "name": Json::string(name),
                      "arguments": Json::string(args),
                    }),
                  }),
                )
              }
              _ => ()
            }
          _ => ()
        }
      }

      let content_value : Json = if text_parts.length() > 0 {
        Json::string(text_parts.join(""))
      } else {
        Json::null()
      }

      if tool_calls.length() > 0 {
        Json::object({
          "role": Json::string("assistant"),
          "content": content_value,
          "tool_calls": Json::array(tool_calls),
        })
      } else {
        Json::object({
          "role": Json::string("assistant"),
          "content": content_value,
        })
      }
    }
    _ =>
      Json::object({
        "role": Json::string("assistant"),
        "content": Json::null(),
      })
  }
}

///|
fn convert_tool_results(msg : ClaudeMessage) -> Array[Json] {
  let tool_messages : Array[Json] = []
  match msg.content {
    Json::Array(arr) =>
      for block in arr {
        match block {
          Json::Object(obj) =>
            match obj.get("type") {
              Some(Json::String("tool_result")) => {
                let tool_use_id = match obj.get("tool_use_id") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
                let content = match obj.get("content") {
                  Some(c) => parse_tool_result_content(c)
                  None => "No content provided"
                }
                tool_messages.push(
                  Json::object({
                    "role": Json::string("tool"),
                    "tool_call_id": Json::string(tool_use_id),
                    "content": Json::string(content),
                  }),
                )
              }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  tool_messages
}

///|
fn parse_tool_result_content(content : Json) -> String {
  match content {
    Json::String(s) => s
    Json::Array(arr) => {
      let parts : Array[String] = []
      for item in arr {
        match item {
          Json::Object(obj) =>
            match obj.get("text") {
              Some(Json::String(t)) => parts.push(t)
              _ => parts.push(item.stringify())
            }
          Json::String(s) => parts.push(s)
          _ => parts.push(item.stringify())
        }
      }
      parts.join("\n")
    }
    _ => content.stringify()
  }
}

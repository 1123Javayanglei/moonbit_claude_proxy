///|
/// Convert OpenAI API responses back to Claude API format.

///|
pub fn convert_openai_to_claude_response(
  openai_response : Map[String, Json],
  original_model : String,
) -> Map[String, Json] {
  let choices = match openai_response.get("choices") {
    Some(Json::Array(arr)) => arr
    _ => abort("No choices in OpenAI response")
  }

  let (content_blocks, finish_reason) = if choices.length() > 0 {
    extract_content_and_finish(choices[0])
  } else {
    (
      [Json::object({ "type": Json::string("text"), "text": Json::string("") })],
      "stop",
    )
  }

  let stop_reason = match finish_reason {
    "stop" => "end_turn"
    "length" => "max_tokens"
    "tool_calls" => "tool_use"
    "function_call" => "tool_use"
    _ => "end_turn"
  }

  let message_id = match openai_response.get("id") {
    Some(Json::String(id)) => id
    _ => "msg_000000000000000000000000"
  }

  let usage_input = match openai_response.get("usage") {
    Some(Json::Object(usage)) =>
      match usage.get("prompt_tokens") {
        Some(Json::Number(n)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
  let usage_output = match openai_response.get("usage") {
    Some(Json::Object(usage)) =>
      match usage.get("completion_tokens") {
        Some(Json::Number(n)) => n.to_int()
        _ => 0
      }
    _ => 0
  }

  let result : Map[String, Json] = {}
  result["id"] = Json::string(message_id)
  result["type"] = Json::string("message")
  result["role"] = Json::string("assistant")
  result["model"] = Json::string(original_model)
  result["content"] = Json::array(content_blocks)
  result["stop_reason"] = Json::string(stop_reason)
  result["stop_sequence"] = Json::null()
  result["usage"] = Json::object({
    "input_tokens": Json::number(usage_input.to_double()),
    "output_tokens": Json::number(usage_output.to_double()),
  })
  result
}

///|
fn extract_content_and_finish(choice : Json) -> (Array[Json], String) {
  let content_blocks : Array[Json] = []
  let mut finish_reason = "stop"

  match choice {
    Json::Object(obj) => {
      finish_reason = match obj.get("finish_reason") {
        Some(Json::String(s)) => s
        _ => "stop"
      }

      match obj.get("message") {
        Some(Json::Object(message)) => {
          match message.get("content") {
            Some(Json::String(text)) if text != "" =>
              content_blocks.push(
                Json::object({
                  "type": Json::string("text"),
                  "text": Json::string(text),
                }),
              )
            _ => ()
          }

          match message.get("tool_calls") {
            Some(Json::Array(tool_calls)) =>
              for tc in tool_calls {
                match tc {
                  Json::Object(tc_obj) =>
                    match tc_obj.get("function") {
                      Some(Json::Object(fn_obj)) => {
                        let fn_name = match fn_obj.get("name") {
                          Some(Json::String(n)) => n
                          _ => ""
                        }
                        let fn_args = match fn_obj.get("arguments") {
                          Some(Json::String(args)) =>
                            @json.parse(args) catch {
                              _ => Json::object({})
                            }
                          _ => Json::object({})
                        }
                        let tc_id = match tc_obj.get("id") {
                          Some(Json::String(id)) => id
                          _ => "tool_00000000"
                        }
                        content_blocks.push(
                          Json::object({
                            "type": Json::string("tool_use"),
                            "id": Json::string(tc_id),
                            "name": Json::string(fn_name),
                            "input": fn_args,
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
        }
        _ => ()
      }
    }
    _ => ()
  }

  if content_blocks.length() == 0 {
    content_blocks.push(
      Json::object({ "type": Json::string("text"), "text": Json::string("") }),
    )
  }

  (content_blocks, finish_reason)
}

///|
pub fn sse_message_start(message_id : String, model : String) -> String {
  let data = Json::object({
    "type": Json::string("message_start"),
    "message": Json::object({
      "id": Json::string(message_id),
      "type": Json::string("message"),
      "role": Json::string("assistant"),
      "model": Json::string(model),
      "content": Json::array([]),
      "stop_reason": Json::null(),
      "stop_sequence": Json::null(),
      "usage": Json::object({
        "input_tokens": Json::number(0.0),
        "output_tokens": Json::number(0.0),
      }),
    }),
  })
  "event: message_start\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_content_block_start(index : Int) -> String {
  let data = Json::object({
    "type": Json::string("content_block_start"),
    "index": Json::number(index.to_double()),
    "content_block": Json::object({
      "type": Json::string("text"),
      "text": Json::string(""),
    }),
  })
  "event: content_block_start\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_ping() -> String {
  let data = Json::object({ "type": Json::string("ping") })
  "event: ping\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_text_delta(index : Int, text : String) -> String {
  let data = Json::object({
    "type": Json::string("content_block_delta"),
    "index": Json::number(index.to_double()),
    "delta": Json::object({
      "type": Json::string("text_delta"),
      "text": Json::string(text),
    }),
  })
  "event: content_block_delta\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_content_block_stop(index : Int) -> String {
  let data = Json::object({
    "type": Json::string("content_block_stop"),
    "index": Json::number(index.to_double()),
  })
  "event: content_block_stop\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_message_delta(
  stop_reason : String,
  input_tokens : Int,
  output_tokens : Int,
) -> String {
  let data = Json::object({
    "type": Json::string("message_delta"),
    "delta": Json::object({
      "stop_reason": Json::string(stop_reason),
      "stop_sequence": Json::null(),
    }),
    "usage": Json::object({
      "input_tokens": Json::number(input_tokens.to_double()),
      "output_tokens": Json::number(output_tokens.to_double()),
    }),
  })
  "event: message_delta\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_message_stop() -> String {
  let data = Json::object({ "type": Json::string("message_stop") })
  "event: message_stop\ndata: \{data.stringify()}\n\n"
}

///|
pub fn sse_error(message : String) -> String {
  let data = Json::object({
    "type": Json::string("error"),
    "error": Json::object({
      "type": Json::string("api_error"),
      "message": Json::string(message),
    }),
  })
  "event: error\ndata: \{data.stringify()}\n\n"
}

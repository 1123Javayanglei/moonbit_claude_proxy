///|
/// HTTP server with API endpoints for the Claude-to-OpenAI proxy.

///|
pub async fn start_server(config : Config) -> Unit {
  let addr_str = "\{config.host}:\{config.port.to_string()}"
  let addr = @socket.Addr::parse(addr_str)
  let server = @http.Server::Server(addr, reuse_addr=true)

  println("Claude-to-OpenAI API Proxy v0.1.0 (MoonBit)")
  println("OpenAI Base URL: \{config.openai_base_url}")
  println("Big Model (opus): \{config.big_model}")
  println("Middle Model (sonnet): \{config.middle_model}")
  println("Small Model (haiku): \{config.small_model}")
  println("Server: \{addr_str}")
  let key_validation = if config.anthropic_api_key is Some(_) {
    "Enabled"
  } else {
    "Disabled"
  }
  println("Client API Key Validation: \{key_validation}")
  println("")

  server.run_forever(
    (request, reader, conn) => handle_request(request, reader, conn, config),
    allow_failure=true,
  )
}

///|
async fn handle_request(
  request : @http.Request,
  reader : &@io.Reader,
  conn : @http.ServerConnection,
  config : Config,
) -> Unit {
  let path = request.path
  let meth = request.meth

  match meth {
    Post =>
      match path {
        "/v1/messages" => handle_messages(request, reader, conn, config)
        "/v1/messages/count_tokens" => handle_count_tokens(reader, conn)
        _ => not_found(conn)
      }
    Get =>
      match path {
        "/health" => handle_health(conn, config)
        "/test-connection" => handle_test_connection(conn, config)
        "/" => handle_root(conn, config)
        _ => not_found(conn)
      }
    _ => {
      conn.send_response(405, "Method Not Allowed")
      conn.end_response()
    }
  }
}

///|
async fn not_found(conn : @http.ServerConnection) -> Unit {
  conn.send_response(404, "Not Found")
  conn.end_response()
}

///|
async fn handle_messages(
  request : @http.Request,
  reader : &@io.Reader,
  conn : @http.ServerConnection,
  config : Config,
) -> Unit {
  // Validate API key if configured
  match config.anthropic_api_key {
    Some(_) => {
      let valid = match request.headers.get("x-api-key") {
        Some(key) => config.validate_client_api_key(key)
        None =>
          match request.headers.get("authorization") {
            Some(auth) if auth.has_prefix("Bearer ") =>
              config.validate_client_api_key(
                auth.substring(start=7, end=auth.length()),
              )
            _ => false
          }
      }
      if !valid {
        send_error(conn, 401, "Invalid API key")
        return
      }
    }
    None => ()
  }

  // Read request body
  let body_text = try {
    let data = reader.read_all()
    data.text()
  } catch {
    _ => {
      send_error(conn, 400, "Failed to read request body")
      return
    }
  }

  let json_result = try? @json.parse(body_text)
  let json = match json_result {
    Ok(j) => j
    Err(_) => {
      send_error(conn, 400, "Invalid JSON body")
      return
    }
  }
  let claude_request = match ClaudeMessagesRequest::from_json(json) {
    Some(req) => req
    None => {
      send_error(conn, 400, "Invalid Claude request format")
      return
    }
  }

  let openai_request = convert_claude_to_openai(claude_request, config)
  let client = OpenAIClient::new(config)

  if claude_request.stream {
    handle_streaming(conn, client, openai_request, claude_request.model)
  } else {
    handle_non_streaming(conn, client, openai_request, claude_request.model)
  }
}

///|
async fn handle_non_streaming(
  conn : @http.ServerConnection,
  client : OpenAIClient,
  openai_request : Map[String, Json],
  original_model : String,
) -> Unit {
  let openai_response = client.chat_completion(openai_request)

  match openai_response.get("error") {
    Some(err) => {
      let msg = match err {
        Json::String(s) => s
        _ => "API error"
      }
      send_error(conn, 500, msg)
    }
    None => {
      let claude_response = convert_openai_to_claude_response(
        openai_response, original_model,
      )
      let response_json = Json::object(claude_response).stringify()

      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      })
      conn.write(response_json)
      conn.end_response()
    }
  }
}

///|
async fn handle_streaming(
  conn : @http.ServerConnection,
  client : OpenAIClient,
  openai_request : Map[String, Json],
  original_model : String,
) -> Unit {
  let sse_lines = client.chat_completion_stream(openai_request)

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "Access-Control-Allow-Origin": "*",
  })

  let message_id = "msg_000000000000000000000000"
  conn.write(sse_message_start(message_id, original_model))
  conn.write(sse_content_block_start(0))
  conn.write(sse_ping())

  let mut final_stop_reason = "end_turn"
  let mut usage_input = 0
  let mut usage_output = 0

  for line in sse_lines {
    if line.has_prefix("data: ") {
      let data_str = line.substring(start=6, end=line.length())
      if data_str == "[DONE]" {
        break
      }

      let chunk = @json.parse(data_str) catch { _ => continue }
      match chunk {
        Json::Object(obj) => {
          match obj.get("usage") {
            Some(Json::Object(usage)) => {
              match usage.get("prompt_tokens") {
                Some(Json::Number(n)) => usage_input = n.to_int()
                _ => ()
              }
              match usage.get("completion_tokens") {
                Some(Json::Number(n)) => usage_output = n.to_int()
                _ => ()
              }
            }
            _ => ()
          }

          match obj.get("choices") {
            Some(Json::Array(choices)) if choices.length() > 0 =>
              match choices[0] {
                Json::Object(choice) => {
                  match choice.get("delta") {
                    Some(Json::Object(delta)) =>
                      match delta.get("content") {
                        Some(Json::String(text)) if text != "" =>
                          conn.write(sse_text_delta(0, text))
                        _ => ()
                      }
                    _ => ()
                  }
                  match choice.get("finish_reason") {
                    Some(Json::String(fr)) if fr != "" =>
                      final_stop_reason = map_finish_reason(fr)
                    _ => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
        }
        _ => continue
      }
    }
  }

  conn.write(sse_content_block_stop(0))
  conn.write(sse_message_delta(final_stop_reason, usage_input, usage_output))
  conn.write(sse_message_stop())
  conn.end_response()
}

///|
fn map_finish_reason(fr : String) -> String {
  match fr {
    "length" => "max_tokens"
    "tool_calls" => "tool_use"
    "function_call" => "tool_use"
    "stop" => "end_turn"
    _ => "end_turn"
  }
}

///|
async fn handle_count_tokens(
  reader : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let body_text = try {
    let data = reader.read_all()
    data.text()
  } catch {
    _ => {
      send_error(conn, 400, "Failed to read body")
      return
    }
  }

  let mut total_chars = 0
  let json = @json.parse(body_text) catch {
    _ =>
      // ignore parse errors
      Json::null()
  }
  match ClaudeTokenCountRequest::from_json(json) {
    Some(req) => {
      match req.system {
        Some(Json::String(s)) => total_chars += s.length()
        Some(Json::Array(arr)) =>
          for block in arr {
            match block {
              Json::Object(obj) =>
                match obj.get("text") {
                  Some(Json::String(t)) => total_chars += t.length()
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
      for msg in req.messages {
        match msg.content {
          Json::String(s) => total_chars += s.length()
          Json::Array(arr) =>
            for block in arr {
              match block {
                Json::Object(obj) =>
                  match obj.get("text") {
                    Some(Json::String(t)) => total_chars += t.length()
                    _ => ()
                  }
                _ => ()
              }
            }
          _ => ()
        }
      }
    }
    None => ()
  }

  let estimated_tokens = if total_chars < 4 { 1 } else { total_chars / 4 }
  let response_str = Json::object({
    "input_tokens": Json::number(estimated_tokens.to_double()),
  }).stringify()

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
  })
  conn.write(response_str)
  conn.end_response()
}

///|
async fn handle_health(conn : @http.ServerConnection, config : Config) -> Unit {
  let data = Json::object({
    "status": Json::string("healthy"),
    "openai_api_configured": Json::boolean(true),
    "client_api_key_validation": if config.anthropic_api_key is Some(_) {
      Json::boolean(true)
    } else {
      Json::boolean(false)
    },
  })
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
  })
  conn.write(data.stringify())
  conn.end_response()
}

///|
async fn handle_test_connection(
  conn : @http.ServerConnection,
  config : Config,
) -> Unit {
  let client = OpenAIClient::new(config)
  let request_body : Map[String, Json] = {}
  request_body["model"] = Json::string(config.small_model)
  request_body["messages"] = Json::array([
    Json::object({
      "role": Json::string("user"),
      "content": Json::string("Hello"),
    }),
  ])
  request_body["max_tokens"] = Json::number(5.0)

  let openai_response = client.chat_completion(request_body)

  match openai_response.get("error") {
    Some(_) => {
      let data = Json::object({
        "status": Json::string("failed"),
        "error_type": Json::string("API Error"),
      }).stringify()
      conn.send_response(503, "Service Unavailable", extra_headers={
        "Content-Type": "application/json",
      })
      conn.write(data)
      conn.end_response()
    }
    None => {
      let data = Json::object({
        "status": Json::string("success"),
        "message": Json::string("Successfully connected to OpenAI API"),
        "model_used": Json::string(config.small_model),
      }).stringify()
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
      })
      conn.write(data)
      conn.end_response()
    }
  }
}

///|
async fn handle_root(conn : @http.ServerConnection, config : Config) -> Unit {
  let data = Json::object({
    "message": Json::string("Claude-to-OpenAI API Proxy v0.1.0 (MoonBit)"),
    "status": Json::string("running"),
    "config": Json::object({
      "openai_base_url": Json::string(config.openai_base_url),
      "max_tokens_limit": Json::number(config.max_tokens_limit.to_double()),
      "big_model": Json::string(config.big_model),
      "small_model": Json::string(config.small_model),
    }),
    "endpoints": Json::object({
      "messages": Json::string("/v1/messages"),
      "count_tokens": Json::string("/v1/messages/count_tokens"),
      "health": Json::string("/health"),
      "test_connection": Json::string("/test-connection"),
    }),
  })
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
  })
  conn.write(data.stringify())
  conn.end_response()
}

///|
async fn send_error(
  conn : @http.ServerConnection,
  code : Int,
  message : String,
) -> Unit {
  let error_str = Json::object({
    "type": Json::string("error"),
    "error": Json::object({
      "type": Json::string("api_error"),
      "message": Json::string(message),
    }),
  }).stringify()

  conn.send_response(code, get_reason(code), extra_headers={
    "Content-Type": "application/json",
  })
  conn.write(error_str)
  conn.end_response()
}

///|
fn get_reason(code : Int) -> String {
  match code {
    200 => "OK"
    400 => "Bad Request"
    401 => "Unauthorized"
    404 => "Not Found"
    405 => "Method Not Allowed"
    500 => "Internal Server Error"
    503 => "Service Unavailable"
    _ => "Unknown"
  }
}

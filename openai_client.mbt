///|
/// Async HTTP client for calling OpenAI-compatible APIs.

///|
pub(all) struct OpenAIClient {
  base_url : String
  api_key : String
  custom_headers : Map[String, String]
}

///|
fn OpenAIClient::new(config : Config) -> OpenAIClient {
  {
    base_url: config.openai_base_url,
    api_key: config.openai_api_key,
    custom_headers: config.get_custom_headers(),
  }
}

///|
fn make_error_map(msg : String) -> Map[String, Json] {
  let err : Map[String, Json] = {}
  err["error"] = Json::string(msg)
  err
}

///|
/// Send a non-streaming chat completion request.
pub async fn OpenAIClient::chat_completion(
  self : OpenAIClient,
  request_body : Map[String, Json],
) -> Map[String, Json] {
  let json_str = Json::object(request_body).stringify()
  let headers = build_headers(self.api_key, self.custom_headers, false)

  let client = @http.Client::Client(self.base_url, headers~)
  defer client.close()

  let response = client.post("/chat/completions", json_str)

  if response.code >= 200 && response.code < 300 {
    let data = client.read_all()
    let body_text_result = try? data.text()
    match body_text_result {
      Ok(body_text) => {
        let json_result = try? @json.parse(body_text)
        match json_result {
          Ok(Json::Object(obj)) => obj
          Ok(_) => make_error_map("Invalid response format")
          Err(_) => make_error_map("Failed to parse: \{body_text}")
        }
      }
      Err(_) => make_error_map("Failed to decode response")
    }
  } else {
    let data = client.read_all()
    let text_result = try? data.text()
    let body_text = match text_result {
      Ok(s) => s
      Err(_) => ""
    }
    make_error_map("HTTP \{response.code.to_string()}: \{body_text}")
  }
}

///|
/// Send a streaming chat completion request.
pub async fn OpenAIClient::chat_completion_stream(
  self : OpenAIClient,
  request_body : Map[String, Json],
) -> Array[String] {
  let json_str = Json::object(request_body).stringify()
  let headers = build_headers(self.api_key, self.custom_headers, true)

  let client = @http.Client::Client(self.base_url, headers~)
  defer client.close()

  client.request(Post, "/chat/completions")
  client.write(json_str)
  let response = client.end_request()

  let lines : Array[String] = []
  if response.code >= 200 && response.code < 300 {
    for ;; {
      match client.read_until("\n") {
        Some(line) => {
          let trimmed = line.trim()
          if trimmed != "" {
            lines.push(trimmed.to_string())
          }
        }
        None => break
      }
    }
  }
  lines
}

///|
/// Build HTTP headers for the request
fn build_headers(
  api_key : String,
  custom_headers : Map[String, String],
  streaming : Bool,
) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["Authorization"] = "Bearer \{api_key}"
  headers["User-Agent"] = "moonbit-claude-proxy/0.1.0"

  custom_headers.each(fn(key, value) { headers[key] = value })

  if streaming {
    headers["Accept"] = "text/event-stream"
  }

  headers
}

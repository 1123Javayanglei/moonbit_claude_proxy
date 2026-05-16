///|
/// Data models for Claude and OpenAI API types.
/// Uses `Json` (from builtin) for dynamic JSON handling.

///|
pub(all) enum ClaudeContentBlock {
  TextBlock(String)
  ImageBlock(String, String)
  ToolUseBlock(String, String, Map[String, Json])
  ToolResultBlock(String, Json)
} derive(Debug)

///|
pub fn ClaudeContentBlock::from_json(json : Json) -> ClaudeContentBlock? {
  guard json is Json::Object(obj) else { return None }
  let typ = match obj.get("type") {
    Some(Json::String(s)) => s
    _ => return None
  }
  match typ {
    "text" =>
      match obj.get("text") {
        Some(Json::String(text)) => Some(TextBlock(text))
        _ => None
      }
    "image" =>
      match obj.get("source") {
        Some(Json::Object(source)) => {
          let media_type = match source.get("media_type") {
            Some(Json::String(mt)) => mt
            _ => return None
          }
          let data = match source.get("data") {
            Some(Json::String(d)) => d
            _ => return None
          }
          Some(ImageBlock(media_type, data))
        }
        _ => None
      }
    "tool_use" => {
      let id = match obj.get("id") {
        Some(Json::String(s)) => s
        _ => return None
      }
      let name = match obj.get("name") {
        Some(Json::String(s)) => s
        _ => return None
      }
      let input = match obj.get("input") {
        Some(Json::Object(m)) => m
        _ => {}
      }
      Some(ToolUseBlock(id, name, input))
    }
    "tool_result" => {
      let tool_use_id = match obj.get("tool_use_id") {
        Some(Json::String(s)) => s
        _ => return None
      }
      let content = match obj.get("content") {
        Some(c) => c
        None => Json::null()
      }
      Some(ToolResultBlock(tool_use_id, content))
    }
    _ => None
  }
}

///|
pub(all) struct ClaudeMessage {
  role : String
  content : Json
} derive(Debug)

///|
pub(all) struct ClaudeTool {
  name : String
  description : String?
  input_schema : Map[String, Json]
} derive(Debug)

///|
pub(all) struct ClaudeMessagesRequest {
  model : String
  max_tokens : Int
  messages : Array[ClaudeMessage]
  system : Json?
  stop_sequences : Array[String]
  stream : Bool
  temperature : Double
  top_p : Double?
  tools : Array[ClaudeTool]
  tool_choice : Map[String, Json]?
} derive(Debug)

///|
pub(all) struct ClaudeTokenCountRequest {
  model : String
  messages : Array[ClaudeMessage]
  system : Json?
  tools : Array[ClaudeTool]
  tool_choice : Map[String, Json]?
} derive(Debug)

///|
pub fn ClaudeMessagesRequest::from_json(json : Json) -> ClaudeMessagesRequest? {
  guard json is Json::Object(obj) else { return None }

  let model = match obj.get("model") {
    Some(Json::String(s)) => s
    _ => return None
  }
  let max_tokens = match obj.get("max_tokens") {
    Some(Number(n)) => n.to_int()
    _ => 4096
  }
  let messages = match obj.get("messages") {
    Some(Array(arr)) => parse_messages(arr)
    _ => return None
  }
  let system = match obj.get("system") {
    Some(s) => Some(s)
    None => None
  }
  let stop_sequences = match obj.get("stop_sequences") {
    Some(Array(arr)) => extract_strings(arr)
    _ => []
  }
  let stream = match obj.get("stream") {
    Some(True) => true
    Some(False) => false
    _ => false
  }
  let temperature = match obj.get("temperature") {
    Some(Number(n)) => n
    _ => 1.0
  }
  let top_p = match obj.get("top_p") {
    Some(Number(n)) => Some(n)
    _ => None
  }
  let tools = match obj.get("tools") {
    Some(Array(arr)) => parse_tools(arr)
    _ => []
  }
  let tool_choice = match obj.get("tool_choice") {
    Some(Json::Object(tc)) => Some(tc)
    _ => None
  }

  Some({
    model,
    max_tokens,
    messages,
    system,
    stop_sequences,
    stream,
    temperature,
    top_p,
    tools,
    tool_choice,
  })
}

///|
fn parse_messages(arr : Array[Json]) -> Array[ClaudeMessage] {
  let msgs : Array[ClaudeMessage] = []
  for item in arr {
    match ClaudeMessage::from_json(item) {
      Some(msg) => msgs.push(msg)
      None => ()
    }
  }
  msgs
}

///|
fn ClaudeMessage::from_json(json : Json) -> ClaudeMessage? {
  guard json is Json::Object(obj) else { return None }
  let role = match obj.get("role") {
    Some(Json::String(s)) => s
    _ => return None
  }
  let content = match obj.get("content") {
    Some(c) => c
    None => Json::null()
  }
  Some({ role, content })
}

///|
fn parse_tools(arr : Array[Json]) -> Array[ClaudeTool] {
  let ts : Array[ClaudeTool] = []
  for item in arr {
    match ClaudeTool::from_json(item) {
      Some(t) => ts.push(t)
      None => ()
    }
  }
  ts
}

///|
fn ClaudeTool::from_json(json : Json) -> ClaudeTool? {
  guard json is Json::Object(obj) else { return None }
  let name = match obj.get("name") {
    Some(Json::String(s)) => s
    _ => return None
  }
  let description = match obj.get("description") {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
  let input_schema = match obj.get("input_schema") {
    Some(Json::Object(schema)) => schema
    _ => return None
  }
  Some({ name, description, input_schema })
}

///|
fn extract_strings(arr : Array[Json]) -> Array[String] {
  let result : Array[String] = []
  for item in arr {
    match item {
      Json::String(s) => result.push(s)
      _ => ()
    }
  }
  result
}

///|
pub fn ClaudeTokenCountRequest::from_json(
  json : Json,
) -> ClaudeTokenCountRequest? {
  guard json is Json::Object(obj) else { return None }

  let model = match obj.get("model") {
    Some(Json::String(s)) => s
    _ => return None
  }
  let messages = match obj.get("messages") {
    Some(Array(arr)) => parse_messages(arr)
    _ => return None
  }
  let system = match obj.get("system") {
    Some(s) => Some(s)
    None => None
  }
  let tools = match obj.get("tools") {
    Some(Array(arr)) => parse_tools(arr)
    _ => []
  }
  let tool_choice = match obj.get("tool_choice") {
    Some(Json::Object(tc)) => Some(tc)
    _ => None
  }

  Some({ model, messages, system, tools, tool_choice })
}

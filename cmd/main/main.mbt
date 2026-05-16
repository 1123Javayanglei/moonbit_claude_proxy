///|
/// Claude Code Proxy - MoonBit Implementation
/// Run with: `moon run cmd/main`

///|
async fn main {
  try! @lib.load_env()
  let config = @lib.Config::load()

  if @env.args().length() > 1 && @env.args()[1] == "--help" {
    print_help(config)
    return
  }

  println("Claude-to-OpenAI API Proxy v0.1.0 (MoonBit)")
  println("")
  println("Configuration:")
  let base_url = config.openai_base_url
  let big = config.big_model
  let middle = config.middle_model
  let small = config.small_model
  let max_tok = config.max_tokens_limit.to_string()
  let timeout = config.request_timeout.to_string()
  let server_addr = "\{config.host}:\{config.port.to_string()}"
  println("  OpenAI Base URL: \{base_url}")
  println("  Big Model (opus): \{big}")
  println("  Middle Model (sonnet): \{middle}")
  println("  Small Model (haiku): \{small}")
  println("  Max Tokens Limit: \{max_tok}")
  println("  Request Timeout: \{timeout}s")
  println("  Server: \{server_addr}")
  let key_val_str = if config.anthropic_api_key is Some(_) {
    "Enabled"
  } else {
    "Disabled"
  }
  println("  Client API Key Validation: \{key_val_str}")
  println("")

  try! @lib.start_server(config)
}

///|
fn print_help(config : @lib.Config) -> Unit {
  println("Claude-to-OpenAI API Proxy v0.1.0 (MoonBit)")
  println("")
  println("Usage: moon run cmd/main")
  println("")
  println("Required environment variables:")
  println("  OPENAI_API_KEY - Your OpenAI API key")
  println("")
  println("Optional environment variables:")
  println("  ANTHROPIC_API_KEY - Expected API key for client validation")
  println(
    "  OPENAI_BASE_URL - OpenAI API base URL (default: https://api.openai.com/v1)",
  )
  println("  BIG_MODEL - Model for opus requests (default: gpt-4o)")
  println("  MIDDLE_MODEL - Model for sonnet requests (default: gpt-4o)")
  println("  SMALL_MODEL - Model for haiku requests (default: gpt-4o-mini)")
  println("  HOST - Server host (default: 0.0.0.0)")
  println("  PORT - Server port (default: 8082)")
  println("  MAX_TOKENS_LIMIT - Token limit (default: 4096)")
  println("  MIN_TOKENS_LIMIT - Minimum token limit (default: 100)")
  println("  REQUEST_TIMEOUT - Request timeout in seconds (default: 90)")
  println("")
  let small = config.small_model
  let middle = config.middle_model
  let big = config.big_model
  println("Model mapping:")
  println("  Claude haiku models -> \{small}")
  println("  Claude sonnet models -> \{middle}")
  println("  Claude opus models -> \{big}")
}

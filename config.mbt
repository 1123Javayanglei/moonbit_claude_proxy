///|
/// Configuration from environment variables.

///|
pub(all) struct Config {
  openai_api_key : String
  anthropic_api_key : String?
  openai_base_url : String
  big_model : String
  middle_model : String
  small_model : String
  host : String
  port : Int
  max_tokens_limit : Int
  min_tokens_limit : Int
  request_timeout : Int
} derive(Debug)

///|
/// Parse env string to Int with default
fn parse_env_int(name : String, default : Int) -> Int {
  match @env.get_env_var(name) {
    Some(s) => @string.parse_int(s) catch { _ => default }
    None => default
  }
}

///|
/// Load config from environment variables.
pub fn Config::load() -> Config {
  let openai_api_key = match @env.get_env_var("OPENAI_API_KEY") {
    Some(key) => key
    None => abort("OPENAI_API_KEY environment variable is required")
  }
  let anthropic_api_key = @env.get_env_var("ANTHROPIC_API_KEY")
  let openai_base_url = @env.get_env_var("OPENAI_BASE_URL").unwrap_or(
    "https://api.openai.com/v1",
  )
  let big_model = @env.get_env_var("BIG_MODEL").unwrap_or("gpt-4o")
  let middle_model = match @env.get_env_var("MIDDLE_MODEL") {
    Some(m) => m
    None => big_model
  }
  let small_model = @env.get_env_var("SMALL_MODEL").unwrap_or("gpt-4o-mini")
  let host = @env.get_env_var("HOST").unwrap_or("0.0.0.0")

  let port = parse_env_int("PORT", 8082)
  let max_tokens_limit = parse_env_int("MAX_TOKENS_LIMIT", 4096)
  let min_tokens_limit = parse_env_int("MIN_TOKENS_LIMIT", 100)
  let request_timeout = parse_env_int("REQUEST_TIMEOUT", 90)

  {
    openai_api_key,
    anthropic_api_key,
    openai_base_url,
    big_model,
    middle_model,
    small_model,
    host,
    port,
    max_tokens_limit,
    min_tokens_limit,
    request_timeout,
  }
}

///|
/// Get custom headers from environment (CUSTOM_HEADER_* variables).
pub fn Config::get_custom_headers(_config : Config) -> Map[String, String] {
  let headers : Map[String, String] = {}
  let env_vars = @env.get_env_vars()
  env_vars.each(fn(key, value) {
    if key.has_prefix("CUSTOM_HEADER_") {
      let header_name = key
        .substring(start=14, end=key.length())
        .replace(old="_", new="-")
      headers[header_name] = value
    }
  })
  headers
}

///|
/// Validate the client API key.
pub fn Config::validate_client_api_key(
  config : Config,
  client_key : String,
) -> Bool {
  match config.anthropic_api_key {
    None => true
    Some(key) => client_key == key
  }
}

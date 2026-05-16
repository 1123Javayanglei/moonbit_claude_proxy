///|
/// Model manager: maps Claude model names to OpenAI model names.

///|
/// Maps Claude model names to OpenAI models.
pub fn map_claude_model_to_openai(
  claude_model : String,
  config : Config,
) -> String {
  let model_lower = claude_model.to_lower()

  if model_lower.has_prefix("gpt-") ||
    model_lower.has_prefix("o1-") ||
    model_lower.has_prefix("ep-") ||
    model_lower.has_prefix("doubao-") ||
    model_lower.has_prefix("deepseek-") {
    return claude_model
  }

  if model_lower.contains("haiku") {
    config.small_model
  } else if model_lower.contains("sonnet") {
    config.middle_model
  } else if model_lower.contains("opus") {
    config.big_model
  } else {
    config.big_model
  }
}

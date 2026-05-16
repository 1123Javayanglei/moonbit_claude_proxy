///|
/// 简易 .env 文件加载。
/// 支持 KEY=VALUE、# 注释、空行、引号包裹的值，以及 export 前缀。

///|
/// 从 .env 文件加载环境变量（默认路径为当前目录下的 `.env`）。
/// 已存在的环境变量不会被覆盖。
pub async fn load_env(path? : String = ".env") -> Unit {
  let file = @fs.read_file(path)
  let text = file.text() catch { _ => return }
  for line in text.split("\n") {
    let line_str = line.to_string().trim().to_string()
    if line_str == "" || line_str.has_prefix("#") {
      continue
    }
    parse_line(line_str)
  }
}

///|
fn parse_line(line : String) -> Unit {
  let mut content = line

  // 去掉 export 前缀
  if content.has_prefix("export ") {
    content = content.substring(start=7, end=content.length()).to_string()
  }

  // 找到第一个 = 分割 key=value
  match content.find("=") {
    Some(eq) => {
      let key = content.substring(start=0, end=eq).trim().to_string()
      if key == "" {
        return
      }
      // 已在环境中则跳过
      if @env.get_env_var(key) is Some(_) {
        return
      }
      let mut value = content.substring(start=eq + 1, end=content.length()).trim().to_string()
      // 去掉双引号
      if value.has_prefix("\"") && value.has_suffix("\"") && value.length() >= 2 {
        value = value.substring(start=1, end=value.length() - 1).to_string()
      } else if value.has_prefix("'") && value.has_suffix("'") && value.length() >= 2 {
        value = value.substring(start=1, end=value.length() - 1).to_string()
      }
      // 去掉行内注释
      match value.find("#") {
        Some(pos) if pos > 0 => {
          value = value.substring(start=0, end=pos).trim().to_string()
        }
        _ => ()
      }
      @env.set_env_var(key, value)
    }
    None => ()
  }
}

///|
fn command_arguments() -> Array[String] {
  // Node supplies both its executable and script path; options starts after argv[0].
  @env.args()[1:].to_owned()
}

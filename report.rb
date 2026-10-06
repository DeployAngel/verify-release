# frozen_string_literal: true

# Given the verdict document `deployangel verify` wrote and its exit code:
# prints the verdict, sets the step's outputs, adds an annotation, and exits
# with the step's result. The summary page was already written by verify.
require "json"
require "deployangel/cli"

Formatter = DeployAngel::CLI::Formatter

# One sentence, then the dashboard link.
def annotate(level, message, link = nil)
  message = message.to_s.strip
  message += "." unless message.end_with?(".", "!", "?")
  message = [ message, link ].compact.join(" ").gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
  puts "::#{level} title=DeployAngel::#{message}"
end

path, code = ARGV[0], Integer(ARGV[1])
document = begin
  text = File.read(path)
  JSON.parse(text) unless text.strip.empty?
rescue SystemCallError, JSON::ParserError
  nil
end
verification = document&.dig("verification") || {}
puts Formatter.verification(document) if document

if (output = ENV["GITHUB_OUTPUT"].to_s) != ""
  File.open(output, "a") do |file|
    { "deployment-id" => document&.dig("deployment", "id"), "verdict" => verification["verdict"],
      "verdict-reason" => verification["verdict_reason"], "state" => verification["state"],
      "dashboard-url" => document&.dig("dashboard_url"), "exit-code" => code }.each { |key, value| file.puts("#{key}=#{value}") }
  end
end

release = document ? "Release #{Formatter.release_name(document)}" : "The release"
statement = document && Formatter.statement(document)
link = document&.dig("dashboard_url")
reason = verification["verdict_reason"].to_s

exit case code
when 0
  annotate("notice", statement || "#{release} cleared", link)
  0
when 6
  annotate("notice", "#{release} has no problems so far, but isn't cleared yet", link)
  0
when 7
  annotate("warning", "#{release} has warnings at its initial check and isn't cleared yet", link)
  0
when 1
  annotate("error", statement || "#{release} failed in production", link)
  1
when 2
  # Not this release's fault: deployed in the app's first day, or replaced
  # by a newer release before it could clear. Notifications skip these too.
  if reason == "warm_up" || reason.start_with?("superseded")
    annotate("notice", statement || "#{release} wasn't cleared", link)
    0
  elsif ENV["INPUT_FAIL_ON_INCONCLUSIVE"] == "false"
    annotate("warning", statement || "#{release} wasn't cleared", link)
    0
  else
    annotate("error", statement || "#{release} wasn't cleared", link)
    1
  end
when 3
  annotate("warning", "#{release} is still being verified; the wait timed out", link)
  0
when 4
  annotate("error", "DeployAngel has no deployment for this commit. Register it (register: true), or check that the token belongs to this app.")
  1
else
  annotate("error", "deployangel verify exited #{code}; see the log above")
  1
end

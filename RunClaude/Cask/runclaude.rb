# Homebrew Cask formula for RunClaude
#
# To install from a custom tap:
#   brew tap your-username/runclaude
#   brew install --cask runclaude
#
# To install from a local file (for testing):
#   brew install --cask ./Cask/runclaude.rb

cask "runclaude" do
  version "0.2.0"
  sha256 "PLACEHOLDER_SHA256"

  # Update this URL after creating a GitHub release
  url "https://github.com/your-username/RunClaude/releases/download/v#{version}/RunClaude-v#{version}.zip"
  name "RunClaude"
  desc "Menu bar app that animates a character based on your Claude Code token usage"
  homepage "https://github.com/your-username/RunClaude"

  depends_on macos: ">= :ventura"

  app "RunClaude.app"

  zap trash: [
    "~/Library/Preferences/com.runclaude.app.plist",
    "~/Library/Caches/com.runclaude.app",
  ]
end

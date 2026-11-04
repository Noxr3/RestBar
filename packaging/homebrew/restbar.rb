cask "restbar" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/Noxr3/RestBar/releases/download/v#{version}/RestBar.zip"
  name "RestBar"
  desc "Keeps your Mac awake while coding agents work, even with the lid closed"
  homepage "https://github.com/Noxr3/RestBar"

  depends_on macos: ">= :ventura"

  app "RestBar.app"

  uninstall quit: "io.github.noxr3.restbar"

  zap delete: "/etc/sudoers.d/restbar",
      trash:  "~/Library/Preferences/io.github.noxr3.restbar.plist"
end

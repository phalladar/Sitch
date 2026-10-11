cask "sitch" do
  version "0.2.0"
  sha256 "115460370936f8973719a640bcc1bdd4e1be1a3b51356969c6a02800a3bf3f0c"

  url "https://github.com/phalladar/Sitch/releases/download/v#{version}/Sitch.dmg"
  name "Sitch"
  desc "Screenshot capture and annotation tool, a free Skitch alternative"
  homepage "https://phalladar.github.io/Sitch/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Sitch.app"

  zap trash: [
    "~/Library/Application Support/Sitch",
    "~/Library/Preferences/io.github.phalladar.Sitch.plist",
  ]
end

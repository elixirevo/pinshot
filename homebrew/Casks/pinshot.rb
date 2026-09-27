cask "pinshot" do
  arch arm: "arm64", intel: "x86_64"

  version "1.2.0"
  sha256 arm:   "REPLACED_DURING_PREPARE",
         intel: "REPLACED_DURING_PREPARE"

  url "https://github.com/elixirevo/pinshot/releases/download/v#{version}/PinShot-#{version}-#{arch}.dmg"
  name "PinShot"
  desc "Capture and pin screenshots as always-on-top windows"
  homepage "https://github.com/elixirevo/pinshot"

  auto_updates true
  depends_on macos: :monterey

  app "PinShot.app"
end

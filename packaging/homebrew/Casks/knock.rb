# frozen_string_literal: true

# Cask di Knock per il tap GGuidotz/homebrew-tap. Version e sha256 li aggiorna release.sh.
cask "knock" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/GGuidotz/knock/releases/download/v#{version}/Knock-#{version}.dmg"
  name "Knock"
  desc "Turns taps on the desk next to your Mac into menu bar switches"
  homepage "https://github.com/GGuidotz/knock"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Knock.app"

  postflight do
    # L'app non è notarizzata (niente account Apple Developer): togliere la quarantena evita "Apri comunque".
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Knock.app"],
                   must_succeed: false
  end

  uninstall quit: "local.knock.app"

  zap trash: [
    "~/Library/Application Support/Knock",
    "~/Library/Preferences/local.knock.app.plist",
  ]

  caveats <<~EOS
    Knock listens with the microphone (macOS shows the orange dot while it listens).
    Sound is never saved or sent. Open Knock and follow the short calibration.
  EOS
end

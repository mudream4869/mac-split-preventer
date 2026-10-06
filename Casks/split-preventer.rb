cask "split-preventer" do
  version "0.1.3"
  sha256 "c7dd78ac3c41ca0abb01420c151823da26190efb605d38656f86f8c758d9e8a5"

  url "https://github.com/mudream4869/mac-split-preventer/releases/download/v#{version}/SplitPreventer-#{version}.zip"
  name "SplitPreventer"
  desc "Splits accidental Split View back into separate full-screen Spaces"
  homepage "https://github.com/mudream4869/mac-split-preventer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "SplitPreventer.app"
  binary "#{appdir}/SplitPreventer.app/Contents/MacOS/SplitPreventer", target: "split-preventer"

  # Ad-hoc signed: drop quarantine so Gatekeeper doesn't block it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/SplitPreventer.app"]
  end

  uninstall quit: "io.github.mudream4869.SplitPreventer"

  zap trash: "~/Library/Logs/SplitPreventer.log"

  caveats <<~EOS
    Grant Accessibility permission in
      System Settings → Privacy & Security → Accessibility

    The app is ad-hoc signed, so the permission is lost on every upgrade:
    remove SplitPreventer from the list and add it again.
  EOS
end

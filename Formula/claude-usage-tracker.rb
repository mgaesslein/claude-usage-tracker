class ClaudeUsageTracker < Formula
  desc "Menu bar app showing AI coding tool usage/quota across accounts"
  homepage "https://github.com/mgaesslein/claude-usage-tracker"
  url "https://github.com/mgaesslein/claude-usage-tracker.git",
      revision: "55a07e19696f4939115855ed958b246a97200c8b"
  version "1.0"
  license "MIT"

  head "https://github.com/mgaesslein/claude-usage-tracker.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"

    app_contents = prefix/"ClaudeUsage.app/Contents"
    (app_contents/"MacOS").install ".build/release/ClaudeUsage"
    app_contents.install "Info.plist"
    system "codesign", "--force", "--deep", "--sign", "-", prefix/"ClaudeUsage.app"
  end

  # Runs unsandboxed (unlike `install`), so it's the right place to place the
  # built app outside the Homebrew prefix.
  def post_install
    installed_app = prefix/"ClaudeUsage.app"
    target = Pathname.new("/Applications/ClaudeUsage.app")
    target.rmtree if target.exist?
    FileUtils.cp_r installed_app, target
  end

  def caveats
    <<~EOS
      ClaudeUsage.app was installed to /Applications. Launch it with:
        open /Applications/ClaudeUsage.app

      `brew uninstall` removes the Homebrew-managed copy but not the one in
      /Applications — remove that yourself with:
        rm -rf /Applications/ClaudeUsage.app
    EOS
  end

  test do
    assert_predicate prefix/"ClaudeUsage.app/Contents/MacOS/ClaudeUsage", :exist?
  end
end

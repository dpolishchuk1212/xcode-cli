class XcodeCli < Formula
  desc "Token-efficient Xcode CLI for coding agents"
  homepage "https://github.com/dpolishchuk1212/xcode-cli"
  url "https://github.com/dpolishchuk1212/xcode-cli/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "2b54dd532f5c0a680117d78c2faaef8102a95d58d2601ba5eb29fff122ecfef1"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/xcode-cli"
  end

  test do
    assert_match "Token-efficient Xcode CLI", shell_output("#{bin}/xcode-cli --help")
  end
end

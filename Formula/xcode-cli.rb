class XcodeCli < Formula
  desc "Token-efficient Xcode CLI for coding agents"
  homepage "https://github.com/dpolishchuk1212/xcode-cli"
  url "https://github.com/dpolishchuk1212/xcode-cli/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "5f9ca5b96c27b503aea20f8ad3597d11425dbec9ce9949c0424837a815ab8d0b"
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

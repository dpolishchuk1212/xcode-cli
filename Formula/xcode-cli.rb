class XcodeCli < Formula
  desc "Token-efficient Xcode CLI for coding agents"
  homepage "https://github.com/dpolishchuk1212/xcode-cli"
  url "https://github.com/dpolishchuk1212/xcode-cli/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "eb13c0d4abf27a1d2d0b47775281689177434d2eedb8c90b3b5858c7493e6683"
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

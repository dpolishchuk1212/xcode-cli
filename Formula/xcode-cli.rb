class XcodeCli < Formula
  desc "Token-efficient Xcode CLI for coding agents"
  homepage "https://github.com/dpolishchuk1212/xcode-cli"
  url "https://github.com/dpolishchuk1212/xcode-cli/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "c96646c6741be6903a7ae83029c717c999b9ed4746ff9a040c59777e1643afd6"
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

class XcodeCli < Formula
  desc "Token-efficient Xcode CLI for coding agents"
  homepage "https://github.com/dpolishchuk1212/xcode-cli"
  url "https://github.com/dpolishchuk1212/xcode-cli/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "1ed4c70be439348733ff21e75c73753d413b651c54cd168e16312da0d5e11962"
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

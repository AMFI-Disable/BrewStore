class Brewstore < Formula
  desc "Terminal companion CLI for BrewStore"
  homepage "https://github.com/amfi-disable/BrewStore"
  url "https://github.com/amfi-disable/BrewStore/raw/main/scripts/brewstore"
  version "1.0.0"
  sha256 "0524458f44ff5cb3e390cbeeb3544ec2f69ec99119934fa79326f5d52c114ce9"
  license "MIT"

  def install
    bin.install "brewstore"
  end

  test do
    assert_match "BrewStore CLI Companion", shell_output("#{bin}/brewstore help")
  end
end

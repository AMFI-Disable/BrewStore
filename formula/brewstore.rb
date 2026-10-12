class Brewstore < Formula
  desc "Terminal companion CLI for BrewStore"
  homepage "https://github.com/AMFI-Disable/BrewStore"
  url "https://github.com/AMFI-Disable/BrewStore/raw/main/scripts/brewstore"
  version "1.0.0"
  sha256 "d73e910f0984531cb494bcad3f396739cf8131e45257da7bfafe2da9b5c42c10"
  license "MIT"

  def install
    bin.install "brewstore"
  end

  test do
    assert_match "BrewStore CLI Companion", shell_output("#{bin}/brewstore help")
  end
end

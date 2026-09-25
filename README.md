<h1 align="center">Retouch</h1>

<p align="center">Resize and reshape images with a small Ruby API and CLI.</p>

<p align="center">
  <a href="https://github.com/rbgfx/retouch/actions/workflows/main.yml"><img src="https://github.com/rbgfx/retouch/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.1+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="MIT license"></a>
</p>

Retouch uses [Tessel](https://github.com/rbgfx/tessel) to read and write PNG, PPM, and BMP images. Its lazy pipelines cover resizing, cropping, rotation, borders, padding, extending, and trimming.

## Install

Until the first RubyGems release, add the repository to your Gemfile:

```ruby
gem "retouch", github: "rbgfx/retouch"
```

## Ruby API

```ruby
require "retouch"

Retouch.open("screenshot.png")
  .resize("640x")
  .border(1, "#303846")
  .save("small.png")
```

Pipelines defer work until `to_image` or `save` and leave the source image unchanged.

## CLI

```sh
retouch screenshot.png resize 640x --filter lanczos3 -o small.png
retouch screenshot.png crop 320x200+40+20 -o crop.png
retouch screenshot.png rotate 90 -o rotated.png
retouch info screenshot.png
```

Geometry accepts `WIDTHxHEIGHT`, `WIDTHx`, `xHEIGHT`, percentages, `!` to stretch, `^` to cover, and `>` to shrink only. Crop offsets may be positive or negative. Resize filters are `nearest`, `bilinear`, `bicubic`, and `lanczos3`.

Outputs are protected from accidental overwrite; use `--force` to replace one. `--dry-run`, `--verbose`, `--quiet`, `--strip`, and `--level 0..9` control a command.

## Development

```sh
bundle install
bundle exec rake verify
```

## License

MIT. See [LICENSE](LICENSE).

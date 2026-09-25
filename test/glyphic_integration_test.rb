# frozen_string_literal: true

require_relative "test_helper"

class GlyphicIntegrationTest < Test::Unit::TestCase
  test "Glyphic renders text with a background band without changing the source" do
    begin
      require "glyphic"
    rescue LoadError
      omit "optional glyphic gem is not installed"
    end

    source = Tessel::Image.new(40, 24)
    result = Retouch::Operations.text(source, "A", x: 8, y: 8, size: 16, color: "#ffffff", background: "#18202ddd", padding: 2)

    assert_equal [0, 0, 0, 0], source[6, 6]
    assert_equal [24, 32, 45, 221], result[6, 6]
    assert_operator result.bytes.bytes.each_slice(4).count { |red, green, blue, alpha| red == 255 && green == 255 && blue == 255 && alpha == 255 }, :>, 0
  end
end

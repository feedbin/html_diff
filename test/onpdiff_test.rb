require "test_helper"

class ONPDiffTest < Minitest::Test
  def test_falls_back_to_delete_and_add_when_edit_limit_is_exceeded
    a = (1..1200).map { |i| "a#{i}" }
    b = (1..1100).map { |i| "b#{i}" }
    diff = ONPDiff.new(a, b).diff
    assert_equal a, diff.reject { |_, op| op == :add }.map(&:first)
    assert_equal b, diff.reject { |_, op| op == :delete }.map(&:first)
  end
end

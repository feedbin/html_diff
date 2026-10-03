require "test_helper"

class SequenceDiffTest < Minitest::Test
  def runs(a, b)
    HTMLDiff::SequenceDiff.new(a, b).runs
  end

  # Rebuild both sides from the runs; every element must be accounted for in order.
  def assert_reconstructs(a, b, result)
    before, after = [], []
    result.each do |op, a_index, b_index, length|
      before.concat(a[a_index, length]) unless op == :add
      after.concat(b[b_index, length]) unless op == :delete
      assert_equal a[a_index, length], b[b_index, length], "common run differs" if op == :common
    end
    assert_equal a, before
    assert_equal b, after
  end

  # Independent dynamic-programming LCS length, used to check minimality.
  def lcs_length(a, b)
    row = Array.new(b.size + 1, 0)
    a.each do |x|
      diagonal = 0
      b.each_with_index do |y, j|
        above = row[j + 1]
        row[j + 1] = x == y ? diagonal + 1 : [row[j], above].max
        diagonal = above
      end
    end
    row.last
  end

  def edit_count(result)
    result.sum { |op, *, length| op == :common ? 0 : length }
  end

  def test_identical
    assert_equal [[:common, 0, 0, 3]], runs(%w[a b c], %w[a b c])
  end

  def test_empty_sides
    assert_equal [], runs([], [])
    assert_equal [[:add, 0, 0, 2]], runs([], %w[a b])
    assert_equal [[:delete, 0, 0, 2]], runs(%w[a b], [])
  end

  def test_replacement_lists_deletions_before_additions
    expected = [[:common, 0, 0, 1], [:delete, 1, 1, 2], [:add, 3, 1, 2], [:common, 3, 3, 1]]
    assert_equal expected, runs(%w[a b c d], %w[a x y d])
  end

  def test_small_random_inputs_are_minimal
    rng = Random.new(42)
    300.times do
      a = Array.new(rng.rand(0..40)) { rng.rand(6) }
      b = Array.new(rng.rand(0..40)) { rng.rand(6) }
      result = runs(a, b)
      assert_reconstructs a, b, result
      assert_equal a.size + b.size - 2 * lcs_length(a, b), edit_count(result), "not minimal for #{a.inspect} #{b.inspect}"
    end
  end

  def test_large_random_inputs_reconstruct
    rng = Random.new(7)
    20.times do
      a = Array.new(rng.rand(500..2000)) { rng.rand(300) }
      b = a.map { |x| rng.rand < 0.1 ? rng.rand(300) : x }
      b.insert(rng.rand(b.size), *Array.new(50) { rng.rand(300) })
      assert_reconstructs a, b, runs(a, b)
    end
  end

  def test_scattered_edits_in_long_sequence_are_found_exactly
    a = (0...20_000).to_a
    b = a.map { |x| (x % 10).zero? ? -x - 1 : x }
    result = runs(a, b)
    assert_reconstructs a, b, result
    assert_equal 4_000, edit_count(result)
  end

  def test_repeated_content_with_many_edits_is_found_exactly
    a = (0...500).to_a * 12
    b = a.each_with_index.map { |x, i| (i % 5).zero? ? -i - 1 : x }
    result = runs(a, b)
    assert_reconstructs a, b, result
    assert_equal 2_400, edit_count(result)
  end

  def test_unrelated_long_sequences_fall_back_to_delete_and_add
    a = (0...3_000).to_a
    b = (3_000...6_000).to_a
    assert_equal [[:delete, 0, 0, 3_000], [:add, 3_000, 0, 3_000]], runs(a, b)
  end
end

# frozen_string_literal: true

module HTMLDiff
  # Diffs two arrays (ideally of integers) and returns runs of
  # [op, a_index, b_index, length], where op is :common, :delete or :add.
  # Each change is listed as its deletions followed by its additions.
  #
  # Common prefixes and suffixes are trimmed first. Small regions, and whole
  # inputs with only a few edits, are solved with Wu's O(NP) algorithm, which
  # gives a minimal diff. Other regions are split on elements that occur
  # equally rarely on each side (patience diff) and solved piece by piece.
  # Regions too different to solve cheaply are reported as deleted then added.
  class SequenceDiff
    # Regions at least this big (both sides combined) are split on anchors.
    PATIENCE_THRESHOLD = 100
    # Give up on a region after this many deletions from its shorter side.
    MAX_EDITS = 1000

    def initialize(a, b)
      @a, @b = a, b
    end

    def runs
      @runs ||= begin
        @runs = []
        @del_length = @add_length = 0
        diff_range(0, @a.size, 0, @b.size, true)
        flush_change
        @runs
      end
    end

    private

    def diff_range(a_lo, a_hi, b_lo, b_hi, top_level = false)
      a, b = @a, @b
      start_a, start_b = a_lo, b_lo
      while a_lo < a_hi && b_lo < b_hi && a[a_lo] == b[b_lo]
        a_lo += 1
        b_lo += 1
      end
      emit_common(start_a, start_b, a_lo - start_a)

      finish = a_hi
      while a_lo < a_hi && b_lo < b_hi && a[a_hi - 1] == b[b_hi - 1]
        a_hi -= 1
        b_hi -= 1
      end

      diff_middle(a_lo, a_hi, b_lo, b_hi, top_level)
      emit_common(a_hi, b_hi, finish - a_hi)
    end

    def diff_middle(a_lo, a_hi, b_lo, b_hi, top_level)
      m, n = a_hi - a_lo, b_hi - b_lo
      return replace(a_lo, a_hi, b_lo, b_hi) if m == 0 || n == 0
      return onp(a_lo, a_hi, b_lo, b_hi) || replace(a_lo, a_hi, b_lo, b_hi) if m + n < PATIENCE_THRESHOLD
      # Documents with only a few edits are cheapest to diff directly, so try
      # that first on a small budget.
      return if top_level && onp(a_lo, a_hi, b_lo, b_hi, (m + n) / 4)

      anchors, max_matches = analyze(a_lo, a_hi, b_lo, b_hi)
      if anchors.any?
        anchors.each do |a_index, b_index|
          diff_range(a_lo, a_index, b_lo, b_index)
          emit_common(a_index, b_index, 1)
          a_lo, b_lo = a_index + 1, b_index + 1
        end
        diff_range(a_lo, a_hi, b_lo, b_hi)
      elsif [m, n].min - max_matches > MAX_EDITS
        replace(a_lo, a_hi, b_lo, b_hi)
      else
        onp(a_lo, a_hi, b_lo, b_hi) || replace(a_lo, a_hi, b_lo, b_hi)
      end
    end

    # Returns anchors, the longest in-order list of [a_index, b_index] pairs for
    # elements that occur equally rarely on both sides (ideally exactly once),
    # and an upper bound on how many elements could match.
    def analyze(a_lo, a_hi, b_lo, b_hi)
      a, b = @a, @b
      a_counts = a[a_lo...a_hi].tally
      b_counts = b[b_lo...b_hi].tally

      max_matches = 0
      rarest = nil
      b_counts.each do |element, count|
        a_count = a_counts[element] or next
        max_matches += count < a_count ? count : a_count
        rarest = count if count == a_count && (rarest.nil? || count < rarest)
      end
      return [[], max_matches] if rarest.nil?

      # Pair the nth occurrence in a with the nth occurrence in b.
      b_positions = {}
      j = b_lo
      while j < b_hi
        element = b[j]
        (b_positions[element] ||= []) << j if b_counts[element] == rarest && a_counts[element] == rarest
        j += 1
      end

      seen = Hash.new(0)
      pairs = []
      i = a_lo
      while i < a_hi
        element = a[i]
        if (positions = b_positions[element])
          pairs << [i, positions[seen[element]]]
          seen[element] += 1
        end
        i += 1
      end

      [longest_increasing(pairs), max_matches]
    end

    # Patience sorting: the longest subsequence of pairs with increasing b_index.
    def longest_increasing(pairs)
      tails = []
      previous = Array.new(pairs.size)
      pairs.each_with_index do |(_, b_index), index|
        position = tails.bsearch_index { |tail| pairs[tail][1] >= b_index } || tails.size
        previous[index] = tails[position - 1] if position > 0
        tails[position] = index
      end

      result = []
      index = tails.last
      while index
        result << pairs[index]
        index = previous[index]
      end
      result.reverse!
    end

    # Wu, Manber, Myers & Miller, "An O(NP) Sequence Comparison Algorithm".
    # Returns false, having emitted nothing, if the region needs more than
    # MAX_EDITS deletions from its shorter side or more than max_steps snakes.
    def onp(a_lo, a_hi, b_lo, b_hi, max_steps = nil)
      swapped = (a_hi - a_lo) > (b_hi - b_lo)
      a, b = swapped ? [@b[b_lo...b_hi], @a[a_lo...a_hi]] : [@a[a_lo...a_hi], @b[b_lo...b_hi]]
      m, n = a.size, b.size
      offset = m + 1
      delta = n - m
      fp = Array.new(m + n + 3, -1)
      path = Array.new(m + n + 3, -1)
      xs, ys, previous = [], [], []

      p = -1
      until fp[delta + offset] == n
        p += 1
        return false if p > MAX_EDITS || (max_steps && xs.size > max_steps)

        k = -p
        while k < delta
          snake(k, offset, a, b, m, n, fp, path, xs, ys, previous)
          k += 1
        end
        k = delta + p
        while k > delta
          snake(k, offset, a, b, m, n, fp, path, xs, ys, previous)
          k -= 1
        end
        snake(delta, offset, a, b, m, n, fp, path, xs, ys, previous)
      end

      nodes = []
      last = path[delta + offset]
      while last != -1
        nodes << last
        last = previous[last]
      end

      # Each node is one edit followed by a run of matches.
      # When swapped, x walks the original b and y the original a.
      x = y = 0
      nodes.reverse_each do |node|
        node_x, node_y = xs[node], ys[node]
        shift = (node_y - node_x) - (y - x)
        if shift > 0
          swapped ? emit_delete(a_lo + y, b_lo + x, shift) : emit_add(a_lo + x, b_lo + y, shift)
          y += shift
        elsif shift < 0
          swapped ? emit_add(a_lo + y, b_lo + x, -shift) : emit_delete(a_lo + x, b_lo + y, -shift)
          x -= shift
        end
        swapped ? emit_common(a_lo + y, b_lo + x, node_x - x) : emit_common(a_lo + x, b_lo + y, node_x - x)
        x, y = node_x, node_y
      end
      true
    end

    def snake(k, offset, a, b, m, n, fp, path, xs, ys, previous)
      from_below = fp[k - 1 + offset] + 1
      from_above = fp[k + 1 + offset]
      if from_below > from_above
        y = from_below
        node = path[k - 1 + offset]
      else
        y = from_above
        node = path[k + 1 + offset]
      end
      x = y - k
      while x < m && y < n && a[x] == b[y]
        x += 1
        y += 1
      end
      path[k + offset] = xs.size
      xs << x
      ys << y
      previous << node
      fp[k + offset] = y
    end

    def replace(a_lo, a_hi, b_lo, b_hi)
      emit_delete(a_lo, b_lo, a_hi - a_lo)
      emit_add(a_hi, b_lo, b_hi - b_lo)
    end

    def emit_common(a_index, b_index, length)
      return if length == 0
      flush_change
      last = @runs.last
      if last && last[0] == :common
        last[3] += length
      else
        @runs << [:common, a_index, b_index, length]
      end
    end

    def emit_delete(a_index, b_index, length)
      return if length == 0
      start_change(a_index, b_index)
      @del_length += length
    end

    def emit_add(a_index, b_index, length)
      return if length == 0
      start_change(a_index, b_index)
      @add_length += length
    end

    def start_change(a_index, b_index)
      return if @del_length > 0 || @add_length > 0
      @change_a, @change_b = a_index, b_index
    end

    def flush_change
      @runs << [:delete, @change_a, @change_b, @del_length] if @del_length > 0
      @runs << [:add, @change_a + @del_length, @change_b, @add_length] if @add_length > 0
      @del_length = @add_length = 0
    end
  end
end

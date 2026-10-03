# frozen_string_literal: true

module HTMLDiff
  # Folds short unchanged text that sits between two changes into them, so a
  # heavily edited passage reads as one replacement instead of confetti.
  # Unchanged text is short when it's at most half the size of the larger side
  # of both neighboring changes. Tags are never folded, since that would
  # duplicate them.
  module Cleanup
    module_function

    # Takes and returns SequenceDiff runs over before_tokens and after_tokens.
    def fold_short_equalities(runs, before_tokens, after_tokens)
      segments = to_segments(runs)
      loop do
        folded = false
        i = 1
        while i < segments.size - 1
          left, middle, right = segments[i - 1], segments[i], segments[i + 1]
          if middle[0] == :common && short?(middle, left, right, before_tokens, after_tokens)
            segments[i - 1, 3] = [[:change, left[1], left[2], right[1] + right[3] - left[1], right[2] + right[4] - left[2]]]
            folded = true
          else
            i += 1
          end
        end
        return to_runs(segments) unless folded
      end
    end

    # Segments are [:common, a_index, b_index, length] or
    # [:change, a_index, b_index, deleted_length, added_length].
    def to_segments(runs)
      runs.each_with_object([]) do |(op, a_index, b_index, length), segments|
        case op
        when :common then segments << [:common, a_index, b_index, length]
        when :delete then segments << [:change, a_index, b_index, length, 0]
        when :add
          if segments.last && segments.last[0] == :change
            segments.last[4] = length
          else
            segments << [:change, a_index, b_index, 0, length]
          end
        end
      end
    end

    def to_runs(segments)
      segments.each_with_object([]) do |(op, a_index, b_index, length, added), runs|
        if op == :common
          runs << [:common, a_index, b_index, length]
        else
          runs << [:delete, a_index, b_index, length] if length > 0
          runs << [:add, a_index + length, b_index, added] if added > 0
        end
      end
    end

    def short?(common, left, right, before_tokens, after_tokens)
      return false unless left[0] == :change && right[0] == :change
      text = after_tokens[common[2], common[3]]
      return false if text.any? { |token| token.start_with?("<") }
      size = text.sum(&:length) * 2
      size <= change_size(left, before_tokens, after_tokens) && size <= change_size(right, before_tokens, after_tokens)
    end

    def change_size(change, before_tokens, after_tokens)
      deleted = before_tokens[change[1], change[3]].sum(&:length)
      added = after_tokens[change[2], change[4]].sum(&:length)
      deleted > added ? deleted : added
    end
  end
end

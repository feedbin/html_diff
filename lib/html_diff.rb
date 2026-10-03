# frozen_string_literal: true

require "nokogiri"
require "cgi/escape"
require "html_diff/version"
require "html_diff/onpdiff"
require "html_diff/tokenizer"
require "html_diff/sequence_diff"
require "html_diff/cleanup"

module HTMLDiff
  class Diff
    MAX_DIFFERENCE = 200

    def initialize(before, after)
      @before = before
      @after = after
    end

    def inline_html
      i = 0
      inline = []
      while i < block_by_block_diff.size
        op_code = block_by_block_diff[i][1]
        if op_code == :common
          inline << block_by_block_diff[i][0]
        else
          if op_code == :delete
            opposite_op_code = :add
            klass = "del"
            first = i
            second = i + 1
          else
            opposite_op_code = :delete
            klass = "ins"
            first = i + 1
            second = i
          end

          if i + 1 < block_by_block_diff.size && block_by_block_diff[i + 1][1] == opposite_op_code
            inline << generate_inline_html(*token_diff(block_by_block_diff[first][0], block_by_block_diff[second][0]))
            i += 1
          else
            inline << add_class_or_wrap_in_tags(block_by_block_diff[i][0], klass)
          end
        end
        i += 1
      end

      "<div class=\"inline-diff\">#{inline.join}</div>"
    end

    def side_by_side_html
      i = 0
      left, right = [], []
      while i < block_by_block_diff.size
        op_code = block_by_block_diff[i][1]
        if op_code == :common
          left << block_by_block_diff[i][0]
          right << block_by_block_diff[i][0]
        else
          if op_code == :delete
            opposite_op_code = :add
            side = left
            klass = "del"
            first = i
            second = i + 1
          else
            opposite_op_code = :delete
            side = right
            klass = "ins"
            first = i + 1
            second = i
          end

          if i + 1 < block_by_block_diff.size && block_by_block_diff[i + 1][1] == opposite_op_code
            deleted, inserted = generate_side_by_side_html(*token_diff(block_by_block_diff[first][0], block_by_block_diff[second][0]))
            left << deleted
            right << inserted
            i += 1
          else
            side << add_class_or_wrap_in_tags(block_by_block_diff[i][0], klass)
          end
        end
        i += 1
      end

      "<div class=\"revision-content\">#{left.join}</div><div class=\"revision-content\">#{right.join}</div>"
    end

    def side_by_side_markdown
      i = 0
      table = ["<table class=\"markdown\">"]
      while i < line_by_line_diff.size
        table << "<tr>"
        op_code = line_by_line_diff[i][1]
        if op_code == :common
          table << "<td>#{line_by_line_diff[i][0]}</td>"
          table << "<td>#{line_by_line_diff[i][0]}</td>"
        else
          if op_code == :delete
            opposite_op_code = :add
            first = i
            second = i + 1
          else
            opposite_op_code = :delete
            first = i + 1
            second = i
          end

          if i + 1 < line_by_line_diff.size && line_by_line_diff[i + 1][1] == opposite_op_code
            before_tokens, after_tokens =
            tokenize_markdown(line_by_line_diff[first][0]),
            tokenize_markdown(line_by_line_diff[second][0])
            if (before_tokens.size - after_tokens.size).abs > MAX_DIFFERENCE
              before_tokens, after_tokens =
              tokenize_line(line_by_line_diff[first][0]),
              tokenize_line(line_by_line_diff[second][0])
            end
            diff = ONPDiff.new(before_tokens, after_tokens).short_diff
            deleted, inserted = generate_side_by_side_markdown(diff)
            table << "<td class=\"diff-del\">#{deleted.join}</td>"
            table << "<td class=\"diff-ins\">#{inserted.join}</td>"
            i += 1
          else
            if op_code == :delete
              table << "<td class=\"diff-del\">#{line_by_line_diff[i][0]}</td>"
              table << "<td></td>"
            else
              table << "<td></td>"
              table << "<td class=\"diff-ins\">#{line_by_line_diff[i][0]}</td>"
            end
          end
        end
        table << "</tr>"
        i += 1
      end
      table << "</table>"

      table.join
    end

    private

    def block_by_block_diff
      @block_by_block_diff ||=
      begin
        before_html = tokenize_html_blocks(@before)
        after_html = tokenize_html_blocks(@after)
        ONPDiff.new(before_html, after_html).paragraph_diff
      end
    end

    def line_by_line_diff
      @line_by_line_diff ||=
      begin
        before_markdown = tokenize_line(CGI.escapeHTML(@before))
        after_markdown = tokenize_line(CGI.escapeHTML(@after))
        ONPDiff.new(before_markdown, after_markdown).short_diff
      end
    end

    def tokenize_line(text)
      text.scan(/[^\r\n]+[\r\n]*/)
    end

    def tokenize_markdown(text)
      t, tokens = [], []
      i = 0
      while i < text.size
        if text[i] =~ /\w/
          t << text[i]
        elsif text[i] =~ /[ \t]/ && t.join =~ /\A\w+\z/
          begin
            t << text[i]
            i += 1
          end while i < text.size && text[i] =~ /[ \t]/
          i -= 1
          tokens << t.join
          t = []
        else
          tokens << t.join if t.size > 0
          tokens << text[i]
          t = []
        end
        i += 1
      end
      tokens << t.join if t.size > 0
      tokens
    end

    def tokenize_html_blocks(html)
      Nokogiri::HTML5.fragment(html).children
        .select { |node| node.element? || (node.text? && !node.content.strip.empty?) }
        .map { |node| node.to_html.tap { |block| block_nodes[block] = node } }
    end

    def block_nodes
      @block_nodes ||= {}
    end

    def tokenize_html(html)
      @child_tokens ||= {}
      Tokenizer.tokenize(block_nodes.fetch(html), child_cache: @child_tokens)
    end

    # Word-level diff of two blocks: their tokens and the SequenceDiff runs.
    def token_diff(before_html, after_html)
      before_tokens = tokenize_html(before_html)
      after_tokens = tokenize_html(after_html)

      # Only the tokens between identical leading and trailing ones are diffed.
      limit = [before_tokens.size, after_tokens.size].min
      prefix = 0
      prefix += 1 while prefix < limit && before_tokens[prefix] == after_tokens[prefix]
      suffix = 0
      suffix += 1 while suffix < limit - prefix && before_tokens[-1 - suffix] == after_tokens[-1 - suffix]

      keys = {}
      ids = {}
      id = ->(token) { ids[token] ||= (keys[Tokenizer.comparison_key(token)] ||= keys.size) }
      a = before_tokens[prefix...before_tokens.size - suffix].map(&id)
      b = after_tokens[prefix...after_tokens.size - suffix].map(&id)

      runs = [[:common, 0, 0, prefix]]
      SequenceDiff.new(a, b).runs.each { |op, a_index, b_index, length| runs << [op, a_index + prefix, b_index + prefix, length] }
      runs << [:common, before_tokens.size - suffix, after_tokens.size - suffix, suffix]
      runs = runs.reject { |run| run[3] == 0 }
      [before_tokens, after_tokens, Cleanup.fold_short_equalities(runs, before_tokens, after_tokens)]
    end

    def add_class_or_wrap_in_tags(html_or_text, klass)
      result = html_or_text.dup
      index_of_next_chevron = result.index(">")
      if result.size > 0 && result[0] == "<" && index_of_next_chevron
        index_of_class = result.index("class=")
        if index_of_class.nil? || index_of_class > index_of_next_chevron
          # we do not have a class for the current tag
          # add it right before the ">"
          result.insert(index_of_next_chevron, " class=\"diff-#{klass}\"")
        else
          # we have a class, insert it at the beginning if not already present
          classes = result[/class=(["'])([^\1]*)\1/, 2]
          if classes.include?("diff-#{klass}")
            result
          else
            result.insert(index_of_class + "class=".size + 1, "diff-#{klass} ")
          end
        end
      else
        "<#{klass}>#{result}</#{klass}>"
      end
    end

    # Unchanged tokens are rendered as they appear after.
    def generate_inline_html(before_tokens, after_tokens, runs)
      inline = []
      runs.each_with_index do |(op, a_index, b_index, length), index|
        case op
        when :common
          inline << after_tokens[b_index, length].join
          # A word that lost its trailing space keeps it as a deletion when
          # removed words follow, so they don't run into it.
          if runs.dig(index + 1, 0) == :delete
            space = before_tokens[a_index + length - 1].delete_prefix(after_tokens[b_index + length - 1])
            inline << add_class_or_wrap_in_tags(space, "del") if space.match?(/\A[ \t]+\z/)
          end
        when :delete
          before_tokens[a_index, length].each { |token| inline << add_class_or_wrap_in_tags(token, "del") }
        when :add
          after_tokens[b_index, length].each { |token| inline << add_class_or_wrap_in_tags(token, "ins") }
        end
      end
      inline.join
    end

    def generate_side_by_side_html(before_tokens, after_tokens, runs)
      deleted, inserted = [], []
      runs.each do |op, a_index, b_index, length|
        case op
        when :common
          deleted << before_tokens[a_index, length].join
          inserted << after_tokens[b_index, length].join
        when :delete
          before_tokens[a_index, length].each { |token| deleted << add_class_or_wrap_in_tags(token, "del") }
        when :add
          after_tokens[b_index, length].each { |token| inserted << add_class_or_wrap_in_tags(token, "ins") }
        end
      end
      [deleted, inserted]
    end

    def generate_side_by_side_markdown(diff)
      deleted, inserted = [], []
      diff.each do |d|
        case d[1]
        when :common
          deleted << d[0]
          inserted << d[0]
        when :delete
          deleted << "<del>#{d[0]}</del>"
        when :add
          inserted << "<ins>#{d[0]}</ins>"
        end
      end
      [deleted, inserted]
    end
  end
end
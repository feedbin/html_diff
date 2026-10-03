# frozen_string_literal: true

module HTMLDiff
  # Turns a parsed HTML node into diffable tokens: tags, words with their
  # trailing spaces, and single non-word characters, all HTML-escaped.
  module Tokenizer
    VOID_ELEMENTS = %w[area base br col embed hr img input link meta source track wbr].freeze
    SKIPPED_CONTENT = %w[script style].freeze
    TEXT_TOKENS = /\w+[ \t]*|\W/
    ESCAPED_TEXT_TOKENS = /&(?:amp|lt|gt|quot|#39);|\w+[ \t]*|\W/
    SPECIAL_CHARACTERS = /[&<>"']/

    module_function

    # Pass a Hash as child_cache to reuse the tokens of a node's child elements
    # that have identical HTML, e.g. unchanged paragraphs across two versions.
    def tokenize(node, tokens = [], child_cache: nil)
      if node.element?
        tokens << start_tag(node)
        unless SKIPPED_CONTENT.include?(node.name)
          node.children.each do |child|
            if child_cache && child.element?
              tokens.concat(child_cache[child.to_html] ||= tokenize(child))
            else
              tokenize(child, tokens)
            end
          end
        end
        tokens << "</#{node.name}>" unless VOID_ELEMENTS.include?(node.name)
      elsif node.text?
        text = node.content
        if text.match?(SPECIAL_CHARACTERS)
          tokens.concat(CGI.escapeHTML(text).scan(ESCAPED_TEXT_TOKENS))
        else
          tokens.concat(text.scan(TEXT_TOKENS))
        end
      end
      tokens
    end

    # What a token is compared by. Start tags of elements with content compare
    # by name only, so attribute changes can't unbalance the markup, and words
    # ignore their trailing spaces.
    def comparison_key(token)
      if token.start_with?("<")
        return token if token.start_with?("</")
        name = token[/\A<([^\s>]+)/, 1]
        VOID_ELEMENTS.include?(name) ? token : "<#{name}>"
      elsif token.end_with?(" ", "\t") && token.match?(/\A\w/)
        token.rstrip
      else
        token
      end
    end

    def start_tag(element)
      attributes = element.attribute_nodes.map do |attribute|
        prefix = attribute.namespace&.prefix
        name = prefix ? "#{prefix}:#{attribute.name}" : attribute.name
        %( #{name}="#{CGI.escapeHTML(attribute.value)}")
      end
      "<#{element.name}#{attributes.join}>"
    end
  end
end

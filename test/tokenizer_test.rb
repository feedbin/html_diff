require "test_helper"

class TokenizerTest < Minitest::Test
  def tokenize(html)
    HTMLDiff::Tokenizer.tokenize(Nokogiri::HTML5.fragment(html).children.first)
  end

  def test_text_is_split_into_words_and_escaped_characters
    expected = ['<p class="a&amp;b">', "AT", "&amp;", "T ", "said ", "&quot;", "hi", "&quot;", " ", "&lt;", "3 ",
      "&amp;", "amp", ";", " ", "it", "&#39;", "s", "</p>"]
    assert_equal expected, tokenize(%(<p class="a&amp;b">AT&amp;T said "hi" &lt;3 &amp;amp; it's</p>))
  end

  def test_script_style_and_comment_content_is_skipped
    expected = ["<p>", "a", "<script>", "</script>", "<style>", "</style>", "b", "</p>"]
    assert_equal expected, tokenize("<p>a<script>x<y</script><style>p{}</style><!-- c -->b</p>")
  end
end

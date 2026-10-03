require "test_helper"
require "open3"
require "rbconfig"

class HTMLDiffTest < Minitest::Test
  def inline(before, after)
    HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{after}</div>").inline_html
  end

  # Text of the output with <ins> (or <del>) removed must equal the text of
  # the before (or after) document: nothing lost, nothing invented. Unchanged
  # words are rendered as they appear after, so the before side is compared
  # ignoring whitespace.
  def assert_text_preserved(before, after, out)
    assert_equal text(before).gsub(/\s+/, ""), text(out, without: "ins").gsub(/\s+/, ""), "before text not recoverable"
    assert_equal text(after), text(out, without: "del"), "after text not recoverable"
  end

  def text(html, without: nil)
    fragment = Nokogiri::HTML5.fragment(html)
    fragment.css(without).each(&:remove) if without
    fragment.text
  end

  def test_keeps_top_level_text
    before, after = "Intro text <p>para</p>", "Intro changed <p>para</p>"
    out = HTMLDiff::Diff.new(before, after).inline_html
    assert_text_preserved before, after, out
  end

  def test_removed_top_level_comment_does_not_swallow_content
    before, after = "<!-- note --><p>a</p>", "<p>a</p>"
    out = HTMLDiff::Diff.new(before, after).inline_html
    assert_text_preserved before, after, out
  end

  def test_unusual_attribute_names_do_not_crash
    before, after = "<p>a</p>", "<p program's>b</p>"
    assert_text_preserved before, after, inline(before, after)
  end

  def test_void_elements_are_not_closed
    picture = '<picture><source srcset="a.webp"><img src="a.jpg"></picture>'
    out = inline("#{picture}<p>a</p>", "#{picture}<p>b</p>")
    assert_includes out, '<picture><source srcset="a.webp"><img src="a.jpg"></picture>'
  end

  def test_replaced_words_show_deletions_first
    assert_equal '<div class="inline-diff"><div><p>The <del>quick </del><del>brown </del><ins>slow </ins><ins>red </ins>fox</p></div></div>',
      inline("<p>The quick brown fox</p>", "<p>The slow red fox</p>")
  end

  def test_short_unchanged_word_between_changes_is_folded_in
    expected = '<div class="inline-diff"><div><p>' \
      "<del>The </del><del>committee </del><del>approved </del><del>the </del><del>new </del><del>budget </del><del>proposal </del><del>yesterday</del>" \
      "<ins>Lawmakers </ins><ins>rejected </ins><ins>the </ins><ins>plan </ins><ins>after </ins><ins>a </ins><ins>long </ins><ins>debate</ins>" \
      ".</p></div></div>"
    assert_equal expected, inline("<p>The committee approved the new budget proposal yesterday.</p>", "<p>Lawmakers rejected the plan after a long debate.</p>")
  end

  def test_unchanged_words_larger_than_neighboring_changes_are_kept
    expected = '<div class="inline-diff"><div><p>' \
      "The <del>quick </del><del>brown </del><ins>slow </ins><ins>red </ins>fox <del>jumps </del><ins>leaps </ins>" \
      "over the <del>lazy </del><del>dog</del><ins>sleepy </ins><ins>cat</ins>.</p></div></div>"
    assert_equal expected, inline("<p>The quick brown fox jumps over the lazy dog.</p>", "<p>The slow red fox leaps over the sleepy cat.</p>")
  end

  def test_tags_between_changes_are_never_folded_in
    expected = '<div class="inline-diff"><div>' \
      "<p><del>aaaa </del><del>bbbb</del><ins>xxxx </ins><ins>yyyy</ins></p>" \
      "<p><del>cccc </del><del>dddd</del><ins>zzzz </ins><ins>wwww</ins></p></div></div>"
    assert_equal expected, inline("<p>aaaa bbbb</p><p>cccc dddd</p>", "<p>xxxx yyyy</p><p>zzzz wwww</p>")
  end

  def test_link_attribute_change_keeps_markup_balanced
    assert_equal '<div class="inline-diff"><div><p>See <a href="http://b.com">this link</a> now</p></div></div>',
      inline('<p>See <a href="http://a.com">this link</a> now</p>', '<p>See <a href="http://b.com">this link</a> now</p>')
  end

  def test_image_source_change_shows_both_images
    assert_equal '<div class="inline-diff"><div><p><img src="a.jpg" class="diff-del"><img src="b.jpg" class="diff-ins"></p></div></div>',
      inline('<p><img src="a.jpg"></p>', '<p><img src="b.jpg"></p>')
  end

  def test_word_gaining_trailing_space_is_unchanged
    assert_equal '<div class="inline-diff"><div><p>the dog <ins>barked</ins></p></div></div>',
      inline("<p>the dog</p>", "<p>the dog barked</p>")
  end

  def test_space_before_removed_words_is_kept
    assert_equal '<div class="inline-diff"><div><p>names<del> </del><del>or </del><del>even </del><del>more</del>, but</p></div></div>',
      inline("<p>names or even more, but</p>", "<p>names, but</p>")
  end

  def test_heavy_rewrite_keeps_all_text
    words = (1..3000).map { |i| "w#{i}" }
    before, after = "<p>#{words.join(" ")}</p>", "<p>#{words.reverse.join(" ")}</p>"
    assert_text_preserved before, after, inline(before, after)
  end

  def test_side_by_side_shows_each_version_of_unchanged_tags
    expected = '<div class="revision-content"><p><a href="a">link</a> <del>x</del></p></div>' \
      '<div class="revision-content"><p><a href="b">link</a> <ins>y</ins></p></div>'
    assert_equal expected, HTMLDiff::Diff.new('<p><a href="a">link</a> x</p>', '<p><a href="b">link</a> y</p>').side_by_side_html
  end

  def test_loads_without_dependencies_preloaded
    lib = File.expand_path("../lib", __dir__)
    script = 'print HTMLDiff::Diff.new("<p>a</p>", "<p>b</p>").inline_html'
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-rhtml_diff", "-e", script)
    assert status.success?, err
    assert_includes out, "<del>a</del>"
    assert_includes out, "<ins>b</ins>"
  end
end

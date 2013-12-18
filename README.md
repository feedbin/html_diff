HTMLDiff
========

Compare HTML and Markdown using inline or side-by-side diffs.

The code for this is extracted from [Discourse](https://github.com/discourse/discourse/). This just packages it as a standalone gem.

Installation
------------

Add this line to your application's Gemfile:

    gem 'html_diff'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install html_diff

Usage
-----

```ruby
require "html_diff"

# Generate inline HTML diff
HTMLDiff::Diff.new(before, after).inline_html

# Generate side-by-side HTML diff
HTMLDiff::Diff.new(before, after).side_by_side_html

# Generate side-by-side Markdown diff
HTMLDiff::Diff.new(before, after).side_by_side_markdown
```
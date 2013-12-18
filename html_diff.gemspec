# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'html_diff/version'

Gem::Specification.new do |spec|
  spec.name          = "html_diff"
  spec.version       = HTMLDiff::VERSION
  spec.authors       = ["Ben Ubois"]
  spec.email         = ["ben@feedbin.me"]
  spec.description   = %q{Compare HTML and Markdown using inline or side-by-side diffs.}
  spec.summary       = %q{Compare HTML and Markdown using inline or side-by-side diffs.}
  spec.homepage      = ""
  spec.license       = "GPLv2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end

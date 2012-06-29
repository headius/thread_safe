# -*- encoding: utf-8 -*-
require File.expand_path('../lib/thread_safe/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Charles Oliver Nutter"]
  gem.email         = ["headius@headius.com"]
  gem.description   = %q{Thread-safe collections and utilities for Ruby}
  gem.summary       = %q{A collection of data structures and utilities to make thread-safe programming in Ruby easier}
  gem.homepage      = "https://github.com/headius/thread_safe"

  gem.files         = `git ls-files`.split($\)
  gem.platform      = 'java' if defined?(JRUBY_VERSION)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "thread_safe"
  gem.require_paths = ["lib"]
  gem.version       = Threadsafe::VERSION
end

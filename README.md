# Threadsafe

[![Build Status](https://travis-ci.org/headius/thread_safe.png)](https://travis-ci.org/headius/thread_safe)

A collection of thread-safe versions of common core Ruby classes.

## Installation

Add this line to your application's Gemfile:

    gem 'thread_safe'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install thread_safe

## Usage

```ruby
require 'thread_safe'

sa = ThreadSafe::Array.new # supports standard Array.new forms
sh = ThreadSafe::Hash.new # supports standard Hash.new forms
```

`ThreadSafe::Cache` also exists, as a hash-like object, and should have
much better performance characteristics under concurrency than
`ThreadSafe::Hash`. However, `ThreadSafe::Cache` is not strictly semantically
equivalent to ruby Hash -- for instance, it does not neccesarily ordered by
insertion time as Hash is. For most uses it should do fine though, and we
recommend you consider `ThreadSafe::Cache` instead of `ThreadSafe::Hash` for your
concurrency-safe hash needs. 


## Contributing

1. Fork it
2. Clone it (`git clone git@github.com:you/thread_safe.git`)
3. Create your feature branch (`git checkout -b my-new-feature`)
4. Build the jar (`rake jar`) NOTE: Requires JRuby
5. Install dependencies (`bundle install`)
6. Commit your changes (`git commit -am 'Added some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create new Pull Request

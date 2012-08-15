require 'thread_safe/version'

module ThreadSafe
  autoload :Cache, 'thread_safe/cache'
  
  if defined?(JRUBY_VERSION)
    require 'jruby/synchronized'

    # A thread-safe subclass of Array. This version locks
    # against the object itself for every method call,
    # ensuring only one thread can be reading or writing
    # at a time. This includes iteration methods like
    # #each.
    class Array < ::Array
      include JRuby::Synchronized
    end

    # A thread-safe subclass of Hash. This version locks
    # against the object itself for every method call,
    # ensuring only one thread can be reading or writing
    # at a time. This includes iteration methods like
    # #each.
    class Hash < ::Hash
      include JRuby::Synchronized
    end
  elsif defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby'
    # Because MRI never runs code in parallel, the existing
    # non-thread-safe structures should usually work fine.
    Array = ::Array
    Hash  = ::Hash
  end
end
require 'thread_safe/version'

if defined?(JRUBY_VERSION)
  require 'jruby/synchronized'
  
  module ThreadSafe
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
  end
else
  # Because MRI never runs code in parallel, the existing
  # non-thread-safe structures should usually work fine.
  module ThreadSafe
    Array = ::Array
    Hash = ::Hash
  end
end
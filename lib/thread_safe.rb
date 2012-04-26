require 'thread_safe/version'

if defined?(JRUBY_VERSION)
  require 'jruby/synchronized'
  
  module ThreadSafe
    class Array < ::Array
      include JRuby::Synchronized
    end
  
    class Hash < ::Hash
      include JRuby::Synchronized
    end
  end
else
  module ThreadSafe
    Array = ::Array
    Hash = ::Hash
  end
end
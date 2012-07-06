module ThreadSafe
  autoload :ConcurrentCacheBackend,    'thread_safe/concurrent_cache_backend'
  autoload :NonConcurrentCacheBackend, 'thread_safe/non_concurrent_cache_backend'
  autoload :SynchronizedCacheBackend,  'thread_safe/synchronized_cache_backend'

  begin
    concurrent_cache_backend = ConcurrentCacheBackend # trigger autoload
  rescue LoadError
  end

  unless concurrent_cache_backend
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby'
      ConcurrentCacheBackend = NonConcurrentCacheBackend
    else
      warn 'ThreadSafe: unsupported Ruby engine, using a fully synchronized ThreadSafe::Cache implementation' if $VERBOSE
      ConcurrentCacheBackend = SynchronizedCacheBackend
    end
  end

  class Cache < ConcurrentCacheBackend
    def initialize(options = nil, &block)
      if options.kind_of?(::Hash)
        validate_options_hash!(options)
      else
        options = nil
      end

      super(options)
      @default_proc = block
    end

    def [](key)
      if value = super
        value
      elsif @default_proc && !key?(key)
        @default_proc.call(self, key)
      else
        value
      end
    end

    def fetch(key)
      if value = self[key]
        value
      elsif !key?(key) && block_given?
        self[key] = yield(key)
      else
        value
      end
    end

    def keys
      arr = []
      each_pair {|k, v| arr << k}
      arr
    end

    def values
      arr = []
      each_pair {|k, v| arr << v}
      arr
    end

    def each_key
      each_pair {|k, v| yield k}
    end

    def each_value
      each_pair {|k, v| yield v}
    end

    def empty?
      each_pair {|k, v| return false}
      true
    end

    private
    def validate_options_hash!(options)
      if (initial_capacity = options[:initial_capacity]) && (!initial_capacity.kind_of?(Fixnum) || initial_capacity < 0)
        raise ArgumentError, ":initial_capacity must be a positive Fixnum"
      end
      if (load_factor = options[:load_factor]) && (!load_factor.kind_of?(Numeric) || load_factor <= 0 || load_factor > 1)
        raise ArgumentError, ":load_factor must be a number between 0 and 1"
      end
      if (concurrency_level = options[:concurrency_level]) && (!concurrency_level.kind_of?(Fixnum) || concurrency_level < 1)
        raise ArgumentError, ":concurrency_level must be a Fixnum greater or equal than 1"
      end
    end
  end
end
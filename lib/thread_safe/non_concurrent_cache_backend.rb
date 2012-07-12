module ThreadSafe
  class NonConcurrentCacheBackend
    # WARNING: all public methods of the class must operate on the @backend directly without calling each other. This is important
    # because of the SynchronizedCacheBackend which uses a non-reentrant mutex for perfomance reasons.
    def initialize(options = nil)
      @backend = {}
    end

    def [](key)
      @backend[key]
    end

    def []=(key, value)
      @backend[key] = value
    end

    def put_if_absent(key, value)
      if @backend.key?(key)
        @backend[key]
      else
        @backend[key] = value
        nil
      end
    end

    def compute_if_absent(key)
      if (stored_value = @backend[key]) || @backend.key?(key)
        stored_value
      else
        @backend[key] = yield
      end
    end

    def replace_pair(key, old_value, new_value)
      if pair?(key, old_value)
        @backend[key] = new_value
        true
      else
        false
      end
    end

    def replace_if_exists(key, new_value)
      if (stored_value = @backend[key]) || @backend.key?(key)
        @backend[key] = new_value
        stored_value
      end
    end

    def key?(key)
      @backend.key?(key)
    end

    def delete(key)
      @backend.delete(key)
    end

    def delete_pair(key, value)
      if pair?(key, value)
        @backend.delete(key)
        true
      else
        false
      end
    end

    def clear
      @backend.clear
      self
    end

    def each_pair
      dupped_backend.each_pair do |k, v|
        yield k, v
      end
      self
    end

    alias_method :_get, :[]
    alias_method :_set, :[]=
    private :_get, :_set
    private
    def dupped_backend
      @backend.dup
    end

    def pair?(key, expected_value)
      ((stored_value = @backend[key]) || @backend.key?(key)) && expected_value.equal?(stored_value)
    end
  end
end
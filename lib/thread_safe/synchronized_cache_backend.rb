module ThreadSafe
  class SynchronizedCacheBackend < NonConcurrentCacheBackend
    require 'mutex_m'
    include Mutex_m

    def [](key)
      synchronize { super }
    end

    def []=(key, value)
      synchronize { super }
    end

    def key?(key)
      synchronize { super }
    end

    def delete(key)
      synchronize { super }
    end

    def clear
      synchronize { super }
    end
  end
end
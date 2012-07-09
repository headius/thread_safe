module ThreadSafe
  class MriCacheBackend < NonConcurrentCacheBackend
    if Thread.respond_to?(:critical)
      def put_if_absent(key, value)
        if stored_value = _get(key)
          stored_value
        else
          disallow_thread_switch { super }
        end
      end

      def replace_if_exists(key, new_value)
        disallow_thread_switch { super }
      end

      def delete_pair(key, value)
        disallow_thread_switch { super }
      end

      private
      def disallow_thread_switch
        prev_critical = Thread.critical
        Thread.critical = true
        yield
      ensure
        Thread.critical = prev_critical
      end
    else
      # There is no `Thread.critical=` on 1.9 (with its GVL/GIL and native threads), we can't prevent it from releasing the GVL while we're performing
      # check-then-act atomic operations (such as put_if_absent), so a global write lock is used by all the write methods. We can get away with a single
      # global lock (instead of a per-instance one) because of the GVL.
      # NOTE: a neat idea of writing a c-ext to manually perform atomic put_if_absent, while relying on Ruby not releasing a GVL while calling
      # a c-ext will not work because of the potentially Ruby implemented `#hash` and `#eql?` key methods.
      WRITE_LOCK = Mutex.new

      def []=(key, value)
        WRITE_LOCK.synchronize { super }
      end

      def put_if_absent(key, value)
        if stored_value = _get(key)
          stored_value
        else
          WRITE_LOCK.synchronize { super }
        end
      end

      def replace_if_exists(key, new_value)
        WRITE_LOCK.synchronize { super }
      end

      def delete(key)
        WRITE_LOCK.synchronize { super }
      end

      def delete_pair(key, value)
        WRITE_LOCK.synchronize { super }
      end

      def clear
        WRITE_LOCK.synchronize { super }
      end
    end
  end
end
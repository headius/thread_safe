module ThreadSafe
  class MriCacheBackend < NonConcurrentCacheBackend
    if Thread.respond_to?(:critical)
      def put_if_absent(key, value)
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
        write_synchronize { super }
      end

      def put_if_absent(key, value)
        write_synchronize { super }
      end

      def delete(key)
        write_synchronize { super }
      end

      def clear
        write_synchronize { super }
      end

      private
      def write_synchronize
        WRITE_LOCK.synchronize { yield }
      end
    end
  end
end
module ThreadSafe
  module Util
    module CheapLockable
      private
      engine = defined?(RUBY_ENGINE) && RUBY_ENGINE
      if engine == 'rbx'
        # Making use of the Rubinius' ability to lock via object headers to avoid the overhead of the extra Mutex objects.
        def cheap_synchronize
          Rubinius.lock(self)
          begin
            yield
          ensure
            Rubinius.unlock(self)
          end
        end

        def cheap_wait(timeout = nil)
          wchan = Rubinius::Channel.new

          begin
            waiters = @waiters ||= []
            waiters.push wchan
            Rubinius.unlock(self)
            signaled = wchan.receive_timeout timeout
          ensure
            Rubinius.lock(self)

            unless signaled or waiters.delete(wchan)
              # we timed out, but got signaled afterwards (e.g. while waiting to
              # acquire @lock), so pass that signal on to the next waiter
              waiters.shift << true unless waiters.empty?
            end
          end

          if timeout
            !!signaled
          else
            self
          end
        end

        def cheap_broadcast
          waiters = @waiters ||= []
          waiters.shift << true until waiters.empty?
          self
        end
      elsif engine == 'jruby'
        # Use Java's native synchronized (this) { wait(); notifyAll(); } to avoid the overhead of the extra Mutex objects
        require 'jruby'

        def cheap_synchronize
          JRuby.reference0(self).synchronized { yield }
        end

        def cheap_wait
          JRuby.reference0(self).wait
        end

        def cheap_broadcast
          JRuby.reference0(self).notify_all
        end
      else
        require 'thread'

        extend Volatile
        attr_volatile :mutex

        def cheap_synchronize
          true until (my_mutex = mutex) || cas_mutex(nil, my_mutex = Mutex.new)
          my_mutex.synchronize { yield }
        end

        def cheap_wait
          conditional_variable = @conditional_variable ||= ConditionVariable.new
          conditional_variable.wait(mutex)
        end

        def cheap_broadcast
          if conditional_variable = @conditional_variable
            conditional_variable.broadcast
          end
        end
      end
    end
  end
end
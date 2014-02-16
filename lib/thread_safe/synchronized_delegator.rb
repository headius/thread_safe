require 'delegate'

# This class provides a trivial way to synchronize all calls to a given object
# by wrapping it with a `Delegator` that performs `Mutex#lock/unlock` calls
# around the delegated `#send`. Example:
#
#   array = [] # not thread-safe on many impls
#   array = SynchronizedDelegator.new([]) # thread-safe
#
# A simple `Mutex` provides a very coarse-grained way to synchronize a given
# object, in that it will cause synchronization for methods that have no
# need for it, but this is a trivial way to get thread-safety where none may
# exist currently on some implementations.
#
# This class is currently being considered for inclusion into stdlib, via
# https://bugs.ruby-lang.org/issues/8556
class SynchronizedDelegator < SimpleDelegator

  def initialize(obj)
    super # __setobj__(obj)
    @mutex = Mutex.new
    undef_cached_methods!
  end

  def method_missing(method, *args, &block)
    mutex = @mutex
    begin
      mutex.lock
      super
    ensure
      mutex.unlock
    end
  end

  private

  if RUBY_VERSION[0, 3] == '1.8'

    def singleton_class
      class << self; self end
    end unless respond_to?(:singleton_class)

    # The 1.8 delegator library does (instance) "eval" all methods
    # delegated on {#initialize}.
    # @see http://rubydoc.info/stdlib/delegate/1.8.7/Delegator
    # @private
    def undef_cached_methods!
      self_class = singleton_class
      for method in self_class.instance_methods(false)
        self_class.send :undef_method, method
      end
    end

    # JRuby 1.8 mode stdlib internals - caching generated modules
    # methods under `Delegator::DelegatorModules` based on class.
    # @private
    def undef_cached_methods!
      gen_mod = DelegatorModules[[__getobj__.class, self.class]]
      if gen_mod && singleton_class.include?(gen_mod)
        self_class = singleton_class
        for method in gen_mod.instance_methods(false)
          self_class.send :undef_method, method
        end
      end
    end if constants.include?('DelegatorModules')

  else

    # Nothing to do since 1.9 {#method_missing} will get called.
    # @private
    def undef_cached_methods!; end

  end

end unless defined?(SynchronizedDelegator)

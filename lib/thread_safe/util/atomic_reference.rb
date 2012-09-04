module ThreadSafe
  module Util
    AtomicReference =
      if defined?(Rubinius::AtomicReference)
        Rubinius::AtomicReference
      else
        require 'atomic'
        defined?(Atomic::InternalReference) ? Atomic::InternalReference : Atomic
      end
  end
end
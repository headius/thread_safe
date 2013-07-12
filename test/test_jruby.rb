require 'test/package.jar'
java_import 'thread_safe.SecurityManager'
manager = SecurityManager.new

# Prevent accessing internal classes
manager.deny java.lang.RuntimePermission.new("accessClassInPackage.sun.misc")
java.lang.System.setSecurityManager manager

require 'test/test_cache'

class TestJRuby < TestCache
end

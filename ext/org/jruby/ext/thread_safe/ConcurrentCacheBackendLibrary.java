package org.jruby.ext.thread_safe;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.jruby.*;
import org.jruby.anno.JRubyClass;
import org.jruby.anno.JRubyMethod;
import org.jruby.runtime.Block;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.runtime.load.Library;

/**
 * Native Java implementation to avoid the JI overhead.
 * 
 * @author thedarkone
 */
public class ConcurrentCacheBackendLibrary implements Library {
    public void load(Ruby runtime, boolean wrap) throws IOException {
        RubyClass jrubyRefClass = runtime.defineClassUnder("ConcurrentCacheBackend", runtime.getObject(), BACKEND_ALLOCATOR, runtime.getModule("ThreadSafe"));
        jrubyRefClass.setAllocator(BACKEND_ALLOCATOR);
        jrubyRefClass.defineAnnotatedMethods(ConcurrentCacheBackend.class);
    }
    
    private static final ObjectAllocator BACKEND_ALLOCATOR = new ObjectAllocator() {
        public IRubyObject allocate(Ruby runtime, RubyClass klazz) {
            return new ConcurrentCacheBackend(runtime, klazz);
        }
    };

    @JRubyClass(name="ConcurrentCacheBackend", parent="Object")
    public static class ConcurrentCacheBackend extends RubyObject {
        // Defaults used by the CHM
        static final int DEFAULT_INITIAL_CAPACITY = 16;
        static final float DEFAULT_LOAD_FACTOR = 0.75f;
        static final int DEFAULT_CONCURRENCY_LEVEL = 16;

        private ConcurrentHashMap<IRubyObject, IRubyObject> map;

        public ConcurrentCacheBackend(Ruby runtime, RubyClass klass) {
            super(runtime, klass);
        }

        @JRubyMethod
        public IRubyObject initialize(ThreadContext context) {
            map = new ConcurrentHashMap<IRubyObject, IRubyObject>();
            return context.getRuntime().getNil();
        }

        @JRubyMethod
        public IRubyObject initialize(ThreadContext context, IRubyObject options) {
            map = toCHM(context, options);
            return context.getRuntime().getNil();
        }

        private ConcurrentHashMap<IRubyObject, IRubyObject> toCHM(ThreadContext context, IRubyObject options) {
            Ruby runtime = context.getRuntime();
            if (!options.isNil() && options.respondsTo("[]")) {
                IRubyObject rInitialCapacity  = options.callMethod(context, "[]", runtime.newSymbol("initial_capacity"));
                IRubyObject rLoadFactor       = options.callMethod(context, "[]", runtime.newSymbol("load_factor"));
                IRubyObject rConcurrencyLevel = options.callMethod(context, "[]", runtime.newSymbol("concurrency_level"));
                int initialCapacity  = !rInitialCapacity.isNil() ?  RubyNumeric.num2int(rInitialCapacity.convertToInteger())  : DEFAULT_INITIAL_CAPACITY;
                float loadFactor     = !rLoadFactor.isNil() ?       (float)RubyNumeric.num2dbl(rLoadFactor.convertToFloat())  : DEFAULT_LOAD_FACTOR;
                int concurrencyLevel = !rConcurrencyLevel.isNil() ? RubyNumeric.num2int(rConcurrencyLevel.convertToInteger()) : DEFAULT_CONCURRENCY_LEVEL;
                return new ConcurrentHashMap<IRubyObject, IRubyObject>(initialCapacity, loadFactor, concurrencyLevel);
            } else {
                return new ConcurrentHashMap<IRubyObject, IRubyObject>();
            }
        }

        @JRubyMethod(name = "[]", required = 1)
        public IRubyObject op_aref(ThreadContext context, IRubyObject key) {
            IRubyObject value;
            return ((value = map.get(key)) == null) ? context.getRuntime().getNil() : value;
        }

        @JRubyMethod(name = {"[]="}, required = 2)
        public IRubyObject op_aset(ThreadContext context, IRubyObject key, IRubyObject value) {
            map.put(key, value);
            return value;
        }

        @JRubyMethod
        public IRubyObject put_if_absent(IRubyObject key, IRubyObject value) {
            IRubyObject result = map.putIfAbsent(key, value);
            return result == null ? getRuntime().getNil() : result;
        }

        @JRubyMethod(name = {"key?"}, required = 1)
        public RubyBoolean has_key_p(IRubyObject key) {
            return map.containsKey(key) ? getRuntime().getTrue() : getRuntime().getFalse();
        }

        @JRubyMethod
        public IRubyObject delete(IRubyObject key) {
            return map.remove(key) == null ? getRuntime().getFalse() : getRuntime().getTrue();
        }

        @JRubyMethod
        public IRubyObject delete_and_get(IRubyObject key) {
            IRubyObject result = map.remove(key);
            return result == null ? getRuntime().getNil() : result;
        }

        @JRubyMethod
        public IRubyObject clear() {
            map.clear();
            return this;
        }

        @JRubyMethod
         public IRubyObject each_pair(ThreadContext context, Block block) {
            for (Map.Entry<IRubyObject,IRubyObject> entry : map.entrySet()) {
                block.yieldSpecific(context, entry.getKey(), entry.getValue());
            }
            return this;
        }
    }
}

package thread_safe;

import java.io.IOException;
        
import org.jruby.Ruby;
import org.jruby.ext.thread_safe.ConcurrentCacheBackendLibrary;
import org.jruby.runtime.load.BasicLibraryService;

public class ConcurrentCacheBackendService implements BasicLibraryService {
    public boolean basicLoad(final Ruby runtime) throws IOException {
        new ConcurrentCacheBackendLibrary().load(runtime, false);
        return true;
    }
}
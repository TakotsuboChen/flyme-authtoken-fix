package io.github.libxposed.api;

import java.lang.reflect.Executable;

/**
 * {@link XposedInterface} 的包装类 <b>编译期桩类</b>。
 *
 * <p>上游实现中模块不直接使用本类，但 {@link XposedModule} 继承自它。
 * 桩里保留同样的继承关系，以便 javac 正确解析继承来的 {@code hook()} /
 * {@code log()} / {@code detach()}。方法体为空，构建时整目录剔除。</p>
 */
public class XposedInterfaceWrapper implements XposedInterface {

    /**
     * 停止当前入口实例接收后续生命周期回调。API 102 新增。
     */
    public final void detach() {
    }

    @Override
    public final int getApiVersion() {
        return LIB_API;
    }

    @Override
    public String getFrameworkName() {
        return null;
    }

    @Override
    public String getFrameworkVersion() {
        return null;
    }

    @Override
    public long getFrameworkVersionCode() {
        return 0L;
    }

    @Override
    public long getFrameworkProperties() {
        return 0L;
    }

    @Override
    public final HookBuilder hook(Executable origin) {
        return null;
    }

    @Override
    public final HookBuilder hookClassInitializer(Class<?> origin) {
        return null;
    }

    @Override
    public boolean deoptimize(Executable executable) {
        return false;
    }

    @Override
    public final void log(int priority, String tag, String msg) {
    }

    @Override
    public final void log(int priority, String tag, String msg, Throwable tr) {
    }
}

package io.github.libxposed.api;

import java.lang.reflect.Executable;
import java.util.List;

/**
 * libxposed API 102 <b>编译期桩类</b>（compileOnly stub）。
 *
 * <p>本仓库不使用 Gradle，构建脚本直接调 {@code javac}。为了让源码能通过类型检查，
 * 这里手写一份与上游 {@code io.github.libxposed:api:102.0.0} 签名一致的桩：
 * 方法与常量齐全、方法体为空。</p>
 *
 * <p>构建脚本会把 {@code io/} 整个目录从 DEX 中剔除（详见 build.sh 第 2 步），
 * 运行时由 LSPosed 框架注入真实现。因此本仓库无需引入任何二进制依赖，
 * 也不会把 API 类打进 APK。</p>
 *
 * <h2>为什么不用上游源码直接编译</h2>
 * <ul>
 *   <li>上游类标注 {@code androidx.annotation.*} 与 {@code io.github.libxposed.annotation.*}，
 *       二者都是仓库外的 Maven 依赖，纯 {@code javac} 环境取不到；</li>
 *   <li>上游 {@code Invoker.Type} 用了 Java 17 的 sealed interface + record，
 *       与 {@code build.sh} 的 {@code -source 8} 目标不一致。</li>
 * </ul>
 * 参考上游源码位于 {@code references/libxposed-api/}，新增 API 调用前请对照其补齐签名，
 * 否则运行时会抛 {@code NoSuchMethodError}。
 */
public interface XposedInterface {

    /** API 版本 101。 */
    int API_101 = 101;

    /** API 版本 102。 */
    int API_102 = 102;

    /** 本库的 API 版本。 */
    int LIB_API = API_102;

    /** 框架具备 hook system_server 及系统进程的能力。 */
    long PROP_CAP_SYSTEM = 1L;

    /** 默认 hook 优先级。 */
    int PRIORITY_DEFAULT = 50;

    /** 拦截链最末端执行。 */
    int PRIORITY_LOWEST = Integer.MIN_VALUE;

    /** 拦截链最前端执行。 */
    int PRIORITY_HIGHEST = Integer.MAX_VALUE;

    /**
     * 拦截器。实现 {@link #intercept(Chain)} 完成对目标方法/构造器的拦截。
     */
    interface Hooker {
        Object intercept(Chain chain) throws Throwable;
    }

    /**
     * 一次调用的拦截链。链对象不可跨线程共享、不可在 {@code intercept()} 返回后复用。
     */
    interface Chain {
        Executable getExecutable();

        Object getThisObject();

        List<Object> getArgs();

        Object getArg(int index);

        Object proceed() throws Throwable;

        Object proceed(Object[] args) throws Throwable;

        Object proceedWith(Object thisObject) throws Throwable;

        Object proceedWith(Object thisObject, Object[] args) throws Throwable;
    }

    /**
     * 某个 hook 的句柄。
     */
    interface HookHandle {
        Executable getExecutable();

        void unhook();

        String getId();

        HookHandle replaceHook(Hooker hooker);
    }

    /**
     * hook 配置构造器。
     */
    interface HookBuilder {
        HookBuilder setPriority(int priority);

        HookBuilder setExceptionMode(ExceptionMode mode);

        HookBuilder setId(String id);

        HookHandle intercept(Hooker hooker);
    }

    /**
     * hooker 异常处理模式。
     */
    enum ExceptionMode {
        DEFAULT,
        PROTECTIVE,
        PASSTHROUGH,
    }

    int getApiVersion();

    String getFrameworkName();

    String getFrameworkVersion();

    long getFrameworkVersionCode();

    long getFrameworkProperties();

    HookBuilder hook(Executable origin);

    HookBuilder hookClassInitializer(Class<?> origin);

    boolean deoptimize(Executable executable);

    void log(int priority, String tag, String msg);

    void log(int priority, String tag, String msg, Throwable tr);
}

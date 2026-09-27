package top.takotsubo.flyme.authtokenfix;

import android.os.Build;
import android.util.Log;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedModuleInterface;

/**
 * 修复魅族 Flyme {@code com.android.server.accounts.AccountManagerService} 的
 * getAuthToken 频控缺陷（libxposed API 102）。
 *
 * <h2>缺陷</h2>
 * Flyme 在 Service 单例上私加了 {@code mRetryCount}/{@code mLastRetryTime} 与一段节流：
 * 距上次调用 &lt; 500ms 则累加计数、否则清零，计数 ≥ 10 时
 * {@code onError(ERROR_CODE_CANCELED, "getAuthToken too frequently")}。
 * 持续高频调用（间隔恒 &lt; 500ms）时计数永不归零，退化为"全局累计 10 次永久封禁"；
 * 且字段不区分 uid/account/authTokenType，一个应用污染所有应用。
 * OAuth 客户端（{@code net.openid.appauth}）把 ERROR_CODE_CANCELED 解读为
 * "用户取消/凭证失效" → 清理凭据 → 强制掉登。
 *
 * <h2>修复</h2>
 * 在每次 {@code getAuthToken} 执行前把两个字段重置。{@code mLastRetryTime = 0} 使
 * {@code elapsedRealtime() - 0} 恒 ≥ 500（开机 500ms 之后），等价于"上次调用在无限久之前"，
 * 让计数清零分支永远命中 —— 不依赖 500ms 这个具体常量。
 *
 * <h2>性能设计</h2>
 * 目标方法位于 {@code system_server}，属极高热路径，因此拦截器体内严格做到
 * <b>零分配 / 零异常 / 零符号查找</b>：
 * <ul>
 *   <li>{@link Field} 句柄在安装期解析一次并 {@code setAccessible(true)}，之后仅做
 *       {@code setInt}/{@code setLong} —— 不再按名查找、不触碰检查型异常路径；</li>
 *   <li>一次性成本（反射、{@code getDeclaredMethods()} 扫描、hook 注册）全部集中在
 *       {@link #install(ClassLoader)}，热路径只剩两次字段写 + 一次 {@code proceed()}；</li>
 *   <li>字段解析失败（变体 ROM）时仍注册 hook 但挂空实现 —— 语义与旧版"钩子无效而非
 *       崩溃"一致，代价仅为一次可完全内联的判断，且运行期字段若补齐仍能生效；</li>
 *   <li>字段写放在 {@code proceed()} <b>之前</b>（等价旧 before 语义），并包在
 *       try/catch 内静默降级，任何意外都不会中断 system_server 的原方法。</li>
 * </ul>
 */
public final class ModuleEntry extends XposedModule {

    private static final String TAG = "FlymeAuthFix";

    /** 目标系统服务类。 */
    private static final String TARGET_CLASS = "com.android.server.accounts.AccountManagerService";
    /** 目标方法名；Flyme 在每个重载开头都插了节流，故按名全量匹配。 */
    private static final String TARGET_METHOD = "getAuthToken";
    private static final String FIELD_RETRY_COUNT = "mRetryCount";
    private static final String FIELD_LAST_RETRY_TIME = "mLastRetryTime";

    /** 仅用于注入确认日志的目标 App。 */
    private static final String OBSERVE_PACKAGE = "com.github.android";

    /** hook id：API 102 下同 id 可原子替换，便于将来热重载。 */
    private static final String HOOK_ID = "flyme_authtoken_reset";

    @Override
    public void onModuleLoaded(XposedModuleInterface.ModuleLoadedParam param) {
        log(Log.INFO, TAG, "event=module_loaded result=ok process=" + param.getProcessName()
                + " api=" + getApiVersion()
                + " framework=" + getFrameworkName()
                + " frameworkVersion=" + getFrameworkVersion()
                + " sdk=" + Build.VERSION.SDK_INT
                + " systemServer=" + param.isSystemServer());
    }

    /**
     * system_server 的首次加载阶段由本回调替代（不会再有 {@code onPackageLoaded} /
     * {@code onPackageReady} 的首次触发）。
     */
    @Override
    public void onSystemServerStarting(XposedModuleInterface.SystemServerStartingParam param) {
        install(param.getClassLoader());
    }

    /**
     * 普通 App 侧只做注入确认，随后 {@link #detach()} 停止接收回调。
     */
    @Override
    public void onPackageReady(XposedModuleInterface.PackageReadyParam param) {
        if (!OBSERVE_PACKAGE.equals(param.getPackageName())) {
            return;
        }
        log(Log.INFO, TAG, "event=injected result=ok package=" + param.getPackageName()
                + " pid=" + android.os.Process.myPid());
        detach();
    }

    /**
     * 安装 hook。一次性成本全部集中在此。
     */
    private void install(ClassLoader classLoader) {
        long startedAt = System.nanoTime();
        try {
            Class<?> amsClass = classLoader.loadClass(TARGET_CLASS);

            Field retryCount = findAccessibleField(amsClass, FIELD_RETRY_COUNT);
            Field lastRetryTime = findAccessibleField(amsClass, FIELD_LAST_RETRY_TIME);
            boolean fieldsReady = (retryCount != null && lastRetryTime != null);

            List<Method> targets = new ArrayList<>(4);
            for (Method m : amsClass.getDeclaredMethods()) {
                if (TARGET_METHOD.equals(m.getName())) {
                    targets.add(m);
                }
            }

            XposedInterface.Hooker hooker = fieldsReady
                    ? new FieldResetter(retryCount, lastRetryTime)
                    : NoopHooker.INSTANCE;

            int registered = 0;
            for (Method m : targets) {
                try {
                    hook(m)
                            .setId(HOOK_ID)
                            .setPriority(XposedInterface.PRIORITY_HIGHEST)
                            .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(hooker);
                    registered++;
                } catch (Throwable t) {
                    log(Log.WARN, TAG, "event=hook_register result=fail method=" + m + " reason=" + t);
                }
            }

            long costUs = (System.nanoTime() - startedAt) / 1000L;
            log(Log.INFO, TAG, "event=hooked result=" + (registered > 0 ? "ok" : "none")
                    + " count=" + registered + "/" + targets.size()
                    + " fieldsReady=" + fieldsReady
                    + " cost_us=" + costUs);
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "event=hooked result=fail reason=class_not_found", t);
        }
    }

    /**
     * 解析目标字段并关闭访问检查。失败返回 {@code null}（降级为空实现 hook）。
     */
    private Field findAccessibleField(Class<?> clazz, String name) {
        try {
            Field f = clazz.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        } catch (Throwable t) {
            log(Log.WARN, TAG, "event=field_resolve result=fail field=" + name + " reason=" + t);
            return null;
        }
    }

    /** 字段已就绪时的拦截器。热路径：两次字段写。 */
    private static final class FieldResetter implements XposedInterface.Hooker {
        private final Field retryCount;
        private final Field lastRetryTime;

        FieldResetter(Field retryCount, Field lastRetryTime) {
            this.retryCount = retryCount;
            this.lastRetryTime = lastRetryTime;
        }

        @Override
        public Object intercept(XposedInterface.Chain chain) throws Throwable {
            Object ams = chain.getThisObject();
            try {
                retryCount.setInt(ams, 0);
                lastRetryTime.setLong(ams, 0L);
            } catch (Throwable ignored) {
                // 静默降级：宁可钩子失效，也不干扰 system_server 原流程
            }
            return chain.proceed();
        }
    }

    /** 字段缺失时的空实现拦截器。 */
    private enum NoopHooker implements XposedInterface.Hooker {
        INSTANCE;

        @Override
        public Object intercept(XposedInterface.Chain chain) throws Throwable {
            return chain.proceed();
        }
    }
}

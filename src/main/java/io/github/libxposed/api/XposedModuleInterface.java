package io.github.libxposed.api;

import android.app.AppComponentFactory;
import android.content.pm.ApplicationInfo;
import android.os.Bundle;

import java.util.List;

/**
 * 模块生命周期接口 <b>编译期桩类</b>。
 *
 * <p>与上游 {@code io.github.libxposed.api.XposedModuleInterface} 相比，桩里省略了
 * {@code @NonNull} / {@code @Nullable} / {@code @RequiresApi} / {@code @SinceApi} 注解
 * ——它们只是编译期提示，省略后模块源码可直接编译，而无需引入 androidx.annotation
 * 与 libxposed:annotation。方法签名与默认实现语义与上游一致。</p>
 */
public interface XposedModuleInterface {

    /** 进程加载信息。 */
    interface ModuleLoadedParam {
        boolean isSystemServer();

        String getProcessName();
    }

    /** 包加载信息（默认 ClassLoader 已就绪，AppComponentFactory 实例化前）。 */
    interface PackageLoadedParam {
        String getPackageName();

        ApplicationInfo getApplicationInfo();

        boolean isFirstPackage();

        ClassLoader getDefaultClassLoader();
    }

    /** 包就绪信息（AppComponentFactory 已创建目标 ClassLoader）。 */
    interface PackageReadyParam extends PackageLoadedParam {
        ClassLoader getClassLoader();

        AppComponentFactory getAppComponentFactory();
    }

    /** system_server 启动信息。 */
    interface SystemServerStartingParam {
        ClassLoader getClassLoader();
    }

    /** 热重载即将发生（旧代码中执行）。API 102 新增。 */
    interface HotReloadingParam {
        Bundle getExtras();

        void setSavedInstanceState(Object outState);
    }

    /** 热重载完成（新代码中执行）。API 102 新增。 */
    interface HotReloadedParam extends ModuleLoadedParam {
        Bundle getExtras();

        Object getSavedInstanceState();

        List<XposedInterface.HookHandle> getOldHookHandles();
    }

    /** 模块 generation 加载进目标进程时回调一次。 */
    default void onModuleLoaded(ModuleLoadedParam param) {
    }

    /** 有代码的包被加载进进程时回调，每个包名一次。 */
    default void onPackageLoaded(PackageLoadedParam param) {
    }

    /** 包 ClassLoader 就绪、即将创建 Application 时回调，每个包名一次。 */
    default void onPackageReady(PackageReadyParam param) {
    }

    /**
     * system_server 即将启动关键服务时回调。
     * <p>在 system_server 中，本回调替代首次的 {@link #onPackageLoaded} /
     * {@link #onPackageReady}，因此 {@code isFirstPackage()} 在那些回调里永不为 true。</p>
     */
    default void onSystemServerStarting(SystemServerStartingParam param) {
    }

    /** 热重载即将发生。返回 {@code true} 才继续。API 102 新增。 */
    default boolean onHotReloading(HotReloadingParam param) {
        return false;
    }

    /** 热重载完成。默认实现会 unhook 全部旧句柄。API 102 新增。 */
    default void onHotReloaded(HotReloadedParam param) {
        for (XposedInterface.HookHandle handle : param.getOldHookHandles()) {
            handle.unhook();
        }
    }
}

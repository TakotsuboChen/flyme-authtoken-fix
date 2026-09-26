package top.takotsubo.flyme.authtokenfix;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

import java.lang.reflect.Method;

public class MainHook implements IXposedHookLoadPackage {
    private static final String TAG = "[FlymeAuthFix] ";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if ("android".equals(lpparam.packageName)) {
            hookSystemServer(lpparam);
        } else if ("com.github.android".equals(lpparam.packageName)) {
            XposedBridge.log(TAG + "Injected into com.github.android successfully!");
        }
    }

    private void hookSystemServer(XC_LoadPackage.LoadPackageParam lpparam) {
        try {
            Class<?> amsClass = XposedHelpers.findClass(
                "com.android.server.accounts.AccountManagerService",
                lpparam.classLoader
            );

            int hookedCount = 0;
            for (Method method : amsClass.getDeclaredMethods()) {
                if ("getAuthToken".equals(method.getName())) {
                    XposedBridge.hookMethod(method, new XC_MethodHook() {
                        @Override
                        protected void beforeHookedMethod(MethodHookParam param) throws Throwable {
                            try {
                                // 彻底重置魅族 Flyme 的防频刷计数器和时间戳
                                XposedHelpers.setIntField(param.thisObject, "mRetryCount", 0);
                                XposedHelpers.setLongField(param.thisObject, "mLastRetryTime", 0L);
                            } catch (Throwable t) {
                                // 忽略特定版本字段微调
                            }
                        }
                    });
                    hookedCount++;
                }
            }

            XposedBridge.log(TAG + "Successfully hooked " + hookedCount + " getAuthToken methods in AccountManagerService!");
        } catch (Throwable t) {
            XposedBridge.log(TAG + "Failed to hook AccountManagerService: " + t.getMessage());
        }
    }
}

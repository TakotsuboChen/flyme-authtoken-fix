package de.robv.android.xposed;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class XposedHelpers {
    public static Class<?> findClass(String className, ClassLoader classLoader) { return null; }
    public static void setIntField(Object obj, String fieldName, int value) {}
    public static void setLongField(Object obj, String fieldName, long value) {}
    public static int getIntField(Object obj, String fieldName) { return 0; }
    public static long getLongField(Object obj, String fieldName) { return 0L; }
    public static Object getObjectField(Object obj, String fieldName) { return null; }
    public static XC_MethodHook.Unhook findAndHookMethod(Class<?> clazz, String methodName, Object... parameterTypesAndCallback) { return null; }
    public static XC_MethodHook.Unhook findAndHookMethod(String className, ClassLoader classLoader, String methodName, Object... parameterTypesAndCallback) { return null; }
}

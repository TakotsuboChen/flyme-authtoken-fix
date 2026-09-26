package de.robv.android.xposed;

import java.lang.reflect.Member;

public abstract class XC_MethodHook {
    public class Unhook {
        public Member getHookedMethod() { return null; }
        public XC_MethodHook getCallback() { return XC_MethodHook.this; }
        public void unhook() {}
    }

    public static class MethodHookParam {
        public Member method;
        public Object thisObject;
        public Object[] args;
        public Object result;
        public Throwable throwable;
        public boolean returnEarly;

        public Object getResult() { return result; }
        public void setResult(Object result) { this.result = result; this.returnEarly = true; }
        public Throwable getThrowable() { return throwable; }
        public void setThrowable(Throwable throwable) { this.throwable = throwable; this.returnEarly = true; }
    }

    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {}
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {}
}

// Minimal Lua 5.3 host over Cheat Engine's lua53-64.dll, used only by tests to run the
// CE-side adapters against mocked memory. C# 5 for Add-Type on Windows PowerShell 5.1.
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ERBS
{
    public sealed class LuaHost : IDisposable
    {
        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string path);
        [DllImport("kernel32", SetLastError = true)] static extern IntPtr GetProcAddress(IntPtr module, string name);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr NewState();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void OpenLibs(IntPtr L);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int LoadBuffer(IntPtr L, byte[] buf, UIntPtr size, string name, string mode);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int PCall(IntPtr L, int nargs, int nresults, int errfunc, IntPtr ctx, IntPtr k);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr ToLString(IntPtr L, int idx, out UIntPtr len);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void SetTop(IntPtr L, int idx);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void Close(IntPtr L);

        readonly IntPtr L;
        readonly LoadBuffer loadBuffer;
        readonly PCall pcall;
        readonly ToLString toLString;
        readonly SetTop setTop;
        readonly Close close;

        static T Fn<T>(IntPtr module, string name) where T : class
        {
            var p = GetProcAddress(module, name);
            if (p == IntPtr.Zero) throw new EntryPointNotFoundException(name);
            return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
        }

        public LuaHost(string dllPath)
        {
            var m = LoadLibrary(dllPath);
            if (m == IntPtr.Zero) throw new DllNotFoundException(dllPath);
            L = Fn<NewState>(m, "luaL_newstate")();
            Fn<OpenLibs>(m, "luaL_openlibs")(L);
            loadBuffer = Fn<LoadBuffer>(m, "luaL_loadbufferx");
            pcall = Fn<PCall>(m, "lua_pcallk");
            toLString = Fn<ToLString>(m, "lua_tolstring");
            setTop = Fn<SetTop>(m, "lua_settop");
            close = Fn<Close>(m, "lua_close");
        }

        // Runs a chunk; returns its first result converted to string (or throws with the Lua error).
        public string Run(string code, string chunkName)
        {
            var bytes = Encoding.UTF8.GetBytes(code);
            int rc = loadBuffer(L, bytes, (UIntPtr)bytes.Length, "@" + chunkName, null);
            if (rc == 0) rc = pcall(L, 0, 1, 0, IntPtr.Zero, IntPtr.Zero);
            UIntPtr len;
            var p = toLString(L, -1, out len);
            string s = p == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(p, (int)len);
            setTop(L, 0);
            if (rc != 0) throw new InvalidOperationException("Lua error: " + s);
            return s;
        }

        public void Dispose() { close(L); }
    }
}

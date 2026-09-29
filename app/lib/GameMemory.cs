// Direct access to the running (offline) Elden Ring process: no Cheat Engine.
// Read/write memory, signature scans, and calling the game's own add-item routine
// through a tiny remote stub. C# 5 for Add-Type on Windows PowerShell 5.1.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ERBS
{
    // Abstraction so the build logic can be unit-tested against mocked memory.
    public interface IMemory
    {
        long ReadInt64(long address);
        int ReadInt32(long address);
        bool WriteInt32(long address, int value);
    }

    public sealed class GameMemory : IMemory, IDisposable
    {
        const uint PROCESS_ACCESS = 0x0002 | 0x0008 | 0x0010 | 0x0020 | 0x0400 | 0x1000; // create thread, vm op/read/write, query info
        const uint MEM_COMMIT_RESERVE = 0x3000, MEM_RELEASE = 0x8000, PAGE_EXECUTE_READWRITE = 0x40;

        [DllImport("kernel32", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
        [DllImport("kernel32", SetLastError = true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
        [DllImport("kernel32", SetLastError = true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, IntPtr size, uint type, uint protect);
        [DllImport("kernel32", SetLastError = true)] static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, IntPtr size, uint type);
        [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr attr, IntPtr stack, IntPtr start, IntPtr param, uint flags, IntPtr id);
        [DllImport("kernel32", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
        [DllImport("kernel32", SetLastError = true)] static extern bool GetExitCodeThread(IntPtr h, out uint code);

        public readonly int Pid;
        public readonly long ModuleBase;
        public readonly int ModuleSize;
        public readonly string FileVersion;
        readonly IntPtr handle;
        readonly List<IntPtr> allocations = new List<IntPtr>();

        GameMemory(Process p)
        {
            Pid = p.Id;
            handle = OpenProcess(PROCESS_ACCESS, false, p.Id);
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open eldenring.exe (is Easy Anti-Cheat running?)");
            var m = p.MainModule;
            ModuleBase = m.BaseAddress.ToInt64();
            ModuleSize = m.ModuleMemorySize;
            FileVersion = m.FileVersionInfo.FileVersion;
            if (ReadInt16(ModuleBase) != 0x5A4D) throw new InvalidOperationException("Game module header unreadable");
        }

        public static GameMemory Attach() { return Attach("eldenring"); }

        public static GameMemory Attach(string processName)
        {
            var ps = Process.GetProcessesByName(processName);
            if (ps.Length == 0) return null;
            return new GameMemory(ps[0]);
        }

        public static GameMemory Attach(Process p) { return new GameMemory(p); }

        public byte[] Read(long address, int size)
        {
            var buf = new byte[size];
            IntPtr read;
            if (!ReadProcessMemory(handle, (IntPtr)address, buf, (IntPtr)size, out read) || read.ToInt64() != size)
                throw new InvalidOperationException(string.Format("Read failed at 0x{0:X}", address));
            return buf;
        }
        public bool TryRead(long address, byte[] buf)
        {
            IntPtr read;
            return ReadProcessMemory(handle, (IntPtr)address, buf, (IntPtr)buf.Length, out read) && read.ToInt64() == buf.Length;
        }
        public short ReadInt16(long a) { return BitConverter.ToInt16(Read(a, 2), 0); }
        public int ReadInt32(long a) { return BitConverter.ToInt32(Read(a, 4), 0); }
        public long ReadInt64(long a) { return BitConverter.ToInt64(Read(a, 8), 0); }
        public bool Write(long address, byte[] data)
        {
            IntPtr written;
            return WriteProcessMemory(handle, (IntPtr)address, data, (IntPtr)data.Length, out written) && written.ToInt64() == data.Length;
        }
        public bool WriteInt32(long a, int v) { return Write(a, BitConverter.GetBytes(v)); }
        public bool WriteInt64(long a, long v) { return Write(a, BitConverter.GetBytes(v)); }

        // Pattern like "48 8B 05 ?? ?? ?? ??". Returns every match inside the main module.
        public List<long> Scan(string pattern)
        {
            var parts = pattern.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            var pat = new int[parts.Length];
            for (int i = 0; i < parts.Length; i++) pat[i] = parts[i].StartsWith("?") ? -1 : Convert.ToInt32(parts[i], 16);
            var hits = new List<long>();
            const int chunk = 1 << 20;
            var buf = new byte[chunk + pat.Length];
            for (long off = 0; off < ModuleSize; off += chunk)
            {
                int len = (int)Math.Min(buf.Length, ModuleSize - off);
                var b = len == buf.Length ? buf : new byte[len];
                if (!TryRead(ModuleBase + off, b)) continue;
                int limit = Math.Min(len - pat.Length, chunk - 1);
                for (int i = 0; i <= limit; i++)
                {
                    int j = 0;
                    while (j < pat.Length && (pat[j] < 0 || b[i + j] == pat[j])) j++;
                    if (j == pat.Length) hits.Add(ModuleBase + off + i);
                }
            }
            return hits;
        }

        public long ScanUnique(string pattern, string what)
        {
            var hits = Scan(pattern);
            if (hits.Count != 1) throw new InvalidOperationException(what + " signature matched " + hits.Count + " times (game version not supported?)");
            return hits[0];
        }

        // Resolves a rip-relative operand: instruction at 'address', disp32 at +dispOffset, instruction length 'length'.
        public long Rip(long address, int dispOffset, int length) { return address + length + ReadInt32(address + dispOffset); }

        public long Alloc(int size)
        {
            var p = VirtualAllocEx(handle, IntPtr.Zero, (IntPtr)size, MEM_COMMIT_RESERVE, PAGE_EXECUTE_READWRITE);
            if (p == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "VirtualAllocEx failed");
            allocations.Add(p);
            return p.ToInt64();
        }

        // Runs code at 'address' on a new game thread and waits for it.
        public uint Execute(long address, long param, uint timeoutMs)
        {
            var t = CreateRemoteThread(handle, IntPtr.Zero, IntPtr.Zero, (IntPtr)address, (IntPtr)param, 0, IntPtr.Zero);
            if (t == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateRemoteThread failed");
            try
            {
                if (WaitForSingleObject(t, timeoutMs) != 0) throw new TimeoutException("Game thread did not finish");
                uint code; GetExitCodeThread(t, out code); return code;
            }
            finally { CloseHandle(t); }
        }

        public void Dispose()
        {
            foreach (var p in allocations) VirtualFreeEx(handle, p, IntPtr.Zero, MEM_RELEASE);
            allocations.Clear();
            CloseHandle(handle);
        }
    }
}

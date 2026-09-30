// Dictionary-backed IMemory for engine tests (compiled together with lib/*.cs by test_engine.ps1).
using System.Collections.Generic;

namespace ERBSTest
{
    public class MockMemory : ERBS.IMemory
    {
        public Dictionary<long, int> Cells = new Dictionary<long, int>();
        public int Writes, FailAt = -1;
        public int ReadInt32(long a) { int v; return Cells.TryGetValue(a, out v) ? v : 0; }
        public long ReadInt64(long a) { return (long)(uint)ReadInt32(a) | ((long)ReadInt32(a + 4) << 32); }
        public bool WriteInt32(long a, int v) { Writes++; if (Writes == FailAt) return false; Cells[a] = v; return true; }
        public void Set64(long a, long v) { Cells[a] = unchecked((int)(v & 0xFFFFFFFF)); Cells[a + 4] = (int)(v >> 32); }
        public void Set32(long a, long v) { Cells[a] = unchecked((int)v); }
        public int U(long a) { return ReadInt32(a); }  // signed, to compare with PowerShell hex literals
    }
}

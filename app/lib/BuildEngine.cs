// Applies a resolved build to the running game: stats, item grants and equipment.
// Every write is read back; nothing is reported as applied without that evidence.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;

namespace ERBS
{
    public sealed class InvRow { public long Address; public uint Handle; public uint Raw; public uint Qty; }

    public sealed class EquipLayout { public int IdBase; public int HandleBase; public string TalismanFormat; public int Evidence; }

    public sealed class EquipRequest { public string Slot; public string Category; public int Id; public int Upgrade; }
    public sealed class EquipResult { public string Slot; public int Id; public string Status; }

    public static class Categories
    {
        public static uint Nibble(string category)
        {
            switch (category) { case "weapon": return 0; case "armor": return 1; case "talisman": return 2; case "goods": return 4; case "ash": return 8; }
            throw new ArgumentException("unsupported category " + category);
        }
        public static uint Raw(string category, int id, int upgrade)
        {
            return (Nibble(category) << 28) | (uint)(id + (category == "weapon" ? upgrade : 0));
        }
    }

    // ---------------------------------------------------------------- memory-only logic (unit tested)

    public static class Inventory
    {
        public const int MaxEntries = 2688;

        static long Q(IMemory m, long a) { try { return m.ReadInt64(a); } catch { return 0; } }
        static int D(IMemory m, long a) { try { return m.ReadInt32(a); } catch { return 0; } }
        static bool Plausible(long p) { return p > 0x10000 && p < 0x7FFFFFFFFFFF; }

        public static List<InvRow> Read(IMemory m, long baseAddr)
        {
            int count = D(m, baseAddr - 8);
            if (count < 0 || count > MaxEntries) throw new InvalidOperationException("inventory count out of range: " + count);
            var rows = new List<InvRow>();
            for (int i = 0; i < count; i++)
            {
                long e = baseAddr + i * 0x18;
                var r = new InvRow { Address = e, Handle = (uint)D(m, e), Raw = (uint)D(m, e + 4), Qty = (uint)D(m, e + 8) };
                if (r.Qty > 0 && r.Handle != 0 && r.Handle != 0xFFFFFFFF && r.Raw != 0xFFFFFFFF) rows.Add(r);
            }
            return rows;
        }

        // Handles currently referenced by the equipment arrays (both known layouts).
        public static HashSet<uint> EquippedHandles(IMemory m, long player)
        {
            var set = new HashSet<uint>();
            for (int off = 0x340; off < 0x3F8; off += 4)
            {
                uint h = (uint)D(m, player + off);
                uint top = h >> 28;
                if (top == 8 || top == 9 || top == 0xA) set.Add(h);
            }
            return set;
        }

        static int Hits(IMemory m, long baseAddr, HashSet<uint> handles)
        {
            int count = D(m, baseAddr - 8);
            if (count < 1 || count > MaxEntries) return 0;
            int hits = 0;
            for (int i = 0; i < count && hits < handles.Count; i++)
                if (handles.Contains((uint)D(m, baseAddr + i * 0x18))) hits++;
            return hits;
        }

        // Finds the main inventory array without hooking game code: it is the array (reachable
        // from PlayerGameData within two pointer hops) that contains the handles of the equipped gear.
        public static long Discover(IMemory m, long player, out string evidence)
        {
            var handles = EquippedHandles(m, player);
            if (handles.Count < 2) { evidence = "too few equipped handles (" + handles.Count + ")"; return 0; }
            var scores = new Dictionary<long, int>();
            var paths = new Dictionary<long, string>();
            Action<long, string> consider = (b, path) =>
            {
                if (!Plausible(b) || scores.ContainsKey(b)) return;
                int h = Hits(m, b, handles);
                scores[b] = h; paths[b] = path;
            };
            for (int o = 0; o < 0x1000; o += 8)
            {
                long v = Q(m, player + o);
                if (!Plausible(v)) continue;
                consider(v, string.Format("[pgd+0x{0:X}]", o));
                for (int o2 = 0; o2 < 0x100; o2 += 8)
                {
                    long w = Q(m, v + o2);
                    consider(w, string.Format("[[pgd+0x{0:X}]+0x{1:X}]", o, o2));
                }
            }
            var ranked = scores.Where(kv => kv.Value > 0).OrderByDescending(kv => kv.Value).ToList();
            if (ranked.Count == 0) { evidence = "no inventory array contains the equipped handles"; return 0; }
            int need = Math.Min(3, handles.Count);
            if (ranked[0].Value < need) { evidence = string.Format("best candidate only matched {0}/{1} handles", ranked[0].Value, handles.Count); return 0; }
            if (ranked.Count > 1 && ranked[1].Value == ranked[0].Value) { evidence = "ambiguous inventory candidates " + paths[ranked[0].Key] + " / " + paths[ranked[1].Key]; return 0; }
            evidence = string.Format("{0} matched {1}/{2} equipped handles", paths[ranked[0].Key], ranked[0].Value, handles.Count);
            return ranked[0].Key;
        }

        public static uint CountOf(List<InvRow> rows, uint raw)
        {
            uint n = 0; foreach (var r in rows) if (r.Raw == raw) n += r.Qty; return n;
        }
    }

    public static class Equipment
    {
        public static readonly Dictionary<string, int> SlotIndex = new Dictionary<string, int> {
            {"L1",0},{"R1",1},{"L2",2},{"R2",3},{"L3",4},{"R3",5},{"Arrow1",6},{"Bolt1",7},{"Arrow2",8},{"Bolt2",9},
            {"Head",12},{"Chest",13},{"Arms",14},{"Legs",15},{"Talisman1",17},{"Talisman2",18},{"Talisman3",19},{"Talisman4",20} };
        const int Count = 22;
        const uint Empty = 0xFFFFFFFF, Unarmed = 110000;
        static readonly int[] IdBaseCandidates = { 0x398, 0x39C };

        static string KindOf(int i) { return i <= 11 ? "weapon" : i <= 15 ? "armor" : i == 16 ? "hair" : "talisman"; }
        static uint U(IMemory m, long a) { try { return (uint)m.ReadInt32(a); } catch { return 0; } }

        static bool Consistent(string kind, uint value, InvRow row, int index, out string format)
        {
            format = "id";
            if (row == null) return false;
            if (kind == "weapon") return row.Raw == value;
            if (kind == "armor") return row.Raw == (0x10000000u | value) && (value % 1000) / 100 == index - 12;
            if (kind == "talisman")
            {
                if (value < 0x10000000 && row.Raw == (0x20000000u | value)) return true;
                if (value == row.Handle) { format = "handle"; return true; }
            }
            return false;
        }

        // Accepts an id-array base only when every occupied slot agrees with the inventory
        // entry its handle points at, and exactly one candidate fits.
        public static EquipLayout Calibrate(IMemory m, long player, List<InvRow> inventory, List<string> report)
        {
            var byHandle = new Dictionary<uint, InvRow>();
            foreach (var r in inventory) byHandle[r.Handle] = r;
            var accepted = new List<EquipLayout>();
            foreach (var idBase in IdBaseCandidates)
            {
                int handleBase = idBase - Count * 4, ok = 0, bad = 0; bool weapon = false, armor = false; string tf = null;
                for (int i = 0; i < Count; i++)
                {
                    string kind = KindOf(i);
                    uint value = U(m, player + idBase + 4 * i), handle = U(m, player + handleBase + 4 * i);
                    if (kind == "hair" || value == Empty || value == 0 || handle == Empty || handle == 0) continue;
                    InvRow row; byHandle.TryGetValue(handle, out row);
                    string fmt; bool good = Consistent(kind, value, row, i, out fmt);
                    if (good) { ok++; if (kind == "weapon") weapon = true; if (kind == "armor") armor = true; if (kind == "talisman" && tf == null) tf = fmt; }
                    else if (!(kind == "weapon" && value == Unarmed)) bad++;
                    report.Add(string.Format("  idBase=0x{0:X} idx={1} {2} value={3} handle={4:X8} {5}", idBase, i, kind, value, handle, good ? "ok" : "MISMATCH"));
                }
                report.Add(string.Format("candidate idBase=0x{0:X} ok={1} bad={2}", idBase, ok, bad));
                if (bad == 0 && ok >= 3 && weapon && armor) accepted.Add(new EquipLayout { IdBase = idBase, HandleBase = handleBase, TalismanFormat = tf ?? "id", Evidence = ok });
            }
            if (accepted.Count == 1) return accepted[0];
            report.Add("accepted candidates=" + accepted.Count + " (need exactly 1)");
            return null;
        }

        public static List<EquipResult> Apply(IMemory m, long player, List<InvRow> inventory, EquipLayout layout, IEnumerable<EquipRequest> requests)
        {
            if (layout == null) throw new InvalidOperationException("equip layout is not calibrated");
            var used = new Dictionary<uint, int>();
            for (int i = 0; i < Count; i++) { uint h = U(m, player + layout.HandleBase + 4 * i); if (h != 0 && h != Empty) used[h] = i; }
            var results = new List<EquipResult>();
            var written = new List<Tuple<int, uint, uint>>();
            try
            {
                foreach (var r in requests)
                {
                    int index; string status;
                    if (!SlotIndex.TryGetValue(r.Slot, out index)) status = "unsupported-slot";
                    else if (KindOf(index) != r.Category) status = "wrong-category";
                    else
                    {
                        uint raw = Categories.Raw(r.Category, r.Id, r.Upgrade);
                        uint oldHandle = U(m, player + layout.HandleBase + 4 * index), oldValue = U(m, player + layout.IdBase + 4 * index);
                        int at; bool currentHere = used.TryGetValue(oldHandle, out at) && at == index;
                        InvRow pick = inventory.FirstOrDefault(x => x.Raw == raw && (!used.ContainsKey(x.Handle) || (currentHere && x.Handle == oldHandle)));
                        if (pick == null) status = inventory.Any(x => x.Raw == raw) ? "already-equipped-elsewhere" : "not-owned";
                        else if (pick.Handle == oldHandle) status = "already-equipped";
                        else
                        {
                            uint value = r.Category == "armor" ? (uint)r.Id : r.Category == "talisman" ? (layout.TalismanFormat == "handle" ? pick.Handle : (uint)r.Id) : raw;
                            written.Add(Tuple.Create(index, oldHandle, oldValue));
                            if (!m.WriteInt32(player + layout.HandleBase + 4 * index, (int)pick.Handle)) throw new InvalidOperationException("handle write failed");
                            if (!m.WriteInt32(player + layout.IdBase + 4 * index, (int)value)) throw new InvalidOperationException("id write failed");
                            if (U(m, player + layout.HandleBase + 4 * index) != pick.Handle || U(m, player + layout.IdBase + 4 * index) != value) throw new InvalidOperationException("equip readback mismatch");
                            used.Remove(oldHandle); used[pick.Handle] = index;
                            status = "equipped";
                        }
                    }
                    results.Add(new EquipResult { Slot = r.Slot, Id = r.Id, Status = status });
                }
            }
            catch (Exception ex)
            {
                for (int k = written.Count - 1; k >= 0; k--)
                {
                    m.WriteInt32(player + layout.HandleBase + 4 * written[k].Item1, (int)written[k].Item2);
                    m.WriteInt32(player + layout.IdBase + 4 * written[k].Item1, (int)written[k].Item3);
                }
                throw new InvalidOperationException(ex.Message + "; equipment rolled back", ex);
            }
            return results;
        }
    }

    // ---------------------------------------------------------------- live game session

    public sealed class GameSession : IDisposable
    {
        public static readonly string[] StatNames = { "vig", "mind", "end", "str", "dex", "int", "fai", "arc" };
        const int StatBase = 0x3C, LevelOffset = 0x68;

        public readonly GameMemory Mem;
        public readonly long GameDataManPtr;
        public long AddItemFunc, ItemManGlobal, Stub, Buffer;
        public readonly List<string> Log = new List<string>();

        public GameSession(GameMemory mem)
        {
            Mem = mem;
            long site = mem.ScanUnique("48 8B 05 ?? ?? ?? ?? 48 85 C0 74 05 48 8B 40 58 C3 C3", "GameDataMan");
            GameDataManPtr = mem.Rip(site, 3, 7);
        }

        public long Player()
        {
            long man = Mem.ReadInt64(GameDataManPtr);
            if (man == 0) return 0;
            return Mem.ReadInt64(man + 8);
        }

        public int[] ReadStats(long player)
        {
            var s = new int[9];
            for (int i = 0; i < 8; i++) s[i] = Mem.ReadInt32(player + StatBase + 4 * i);
            s[8] = Mem.ReadInt32(player + LevelOffset);
            return s;
        }

        // Writes only the given stats, verifies all eight and the unchanged level, rolls back on mismatch.
        public void WriteStats(long player, IDictionary<string, int> stats)
        {
            var before = ReadStats(player);
            for (int i = 0; i < 8; i++) if (before[i] < 1 || before[i] > 99) throw new InvalidOperationException("character stats look invalid; refusing to write");
            try
            {
                foreach (var kv in stats)
                {
                    int i = Array.IndexOf(StatNames, kv.Key);
                    if (i < 0 || kv.Value < 1 || kv.Value > 99) throw new ArgumentException("invalid stat " + kv.Key);
                    if (!Mem.WriteInt32(player + StatBase + 4 * i, kv.Value)) throw new InvalidOperationException("stat write failed");
                }
                var after = ReadStats(player);
                for (int i = 0; i < 8; i++) { int want = stats.ContainsKey(StatNames[i]) ? stats[StatNames[i]] : before[i]; if (after[i] != want) throw new InvalidOperationException("stat readback mismatch: " + StatNames[i]); }
                if (after[8] != before[8]) throw new InvalidOperationException("level changed unexpectedly");
            }
            catch
            {
                for (int i = 0; i < 8; i++) Mem.WriteInt32(player + StatBase + 4 * i, before[i]);
                throw;
            }
        }

        // Builds a small stub that calls the game's own add-item routine (same call the Hexinton
        // table uses): rcx = item manager, rdx = &buffer[0x20], r8 = &buffer, r9 = 0.
        public void PrepareGrant()
        {
            if (Stub != 0) return;
            AddItemFunc = Mem.ScanUnique("40 55 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 ?? ?? ?? ?? 48 81 EC ?? ?? ?? ?? 48 C7 45 C8 ?? ?? ?? ?? 48 89 9C 24 ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 ?? ?? ?? ?? 44 89 4C 24 ?? 4D 8B F8", "AddItem");
            long site = Mem.ScanUnique("44 8B 61 1C 41 8B FC C1 EF 07 40 80 E7 01 41 C1 EC 08 41 80 E4 01 48 8B 0D", "item manager");
            ItemManGlobal = Mem.Rip(site + 0x16, 3, 7);
            long mem = Mem.Alloc(0x200);
            Buffer = mem; Stub = mem + 0x100;
            var code = new List<byte>();
            code.AddRange(new byte[] { 0x48, 0x83, 0xEC, 0x28 });                         // sub rsp,28
            code.AddRange(new byte[] { 0x48, 0xB8 }); code.AddRange(BitConverter.GetBytes(ItemManGlobal)); // mov rax,&global
            code.AddRange(new byte[] { 0x48, 0x8B, 0x08 });                               // mov rcx,[rax]
            code.AddRange(new byte[] { 0x48, 0x85, 0xC9, 0x74, 0x23 });                   // test rcx,rcx ; jz exit
            code.AddRange(new byte[] { 0x48, 0xBA }); code.AddRange(BitConverter.GetBytes(Buffer + 0x20)); // mov rdx,&buf+20
            code.AddRange(new byte[] { 0x49, 0xB8 }); code.AddRange(BitConverter.GetBytes(Buffer));        // mov r8,&buf
            code.AddRange(new byte[] { 0x45, 0x31, 0xC9 });                               // xor r9d,r9d
            code.AddRange(new byte[] { 0x48, 0xB8 }); code.AddRange(BitConverter.GetBytes(AddItemFunc));  // mov rax,AddItem
            code.AddRange(new byte[] { 0xFF, 0xD0 });                                     // call rax
            code.AddRange(new byte[] { 0x48, 0x83, 0xC4, 0x28, 0xC3 });                   // exit: add rsp,28 ; ret
            if (!Mem.Write(Stub, code.ToArray())) throw new InvalidOperationException("stub write failed");
        }

        // +0x00: dword read through r8 ("ItemSpawnData2" in the Hexinton table, FFFFFFFF). It must be -1: with 0 the
        // game creates weapon/armor/ash instances that the inventory never shows. Confirmed live 2026-09-29: with 0
        // a granted shield was invisible; with -1 a granted Dagger appeared in the inventory. Goods ignore it.
        static readonly ulong[] BufferTemplate = { 0xFFFFFFFFFFFFFFFF, 0, 0, 0, 0xF00006AE00000001, 1, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF00000000, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF00000000 };

        public void Grant(uint raw, int quantity)
        {
            PrepareGrant();
            if (Mem.ReadInt64(ItemManGlobal) == 0) throw new InvalidOperationException("item manager not ready (load into the world first)");
            var bytes = new List<byte>();
            foreach (var q in BufferTemplate) bytes.AddRange(BitConverter.GetBytes(q));
            var b = bytes.ToArray();
            BitConverter.GetBytes(raw).CopyTo(b, 0x24);
            BitConverter.GetBytes(quantity).CopyTo(b, 0x28);
            BitConverter.GetBytes(-1).CopyTo(b, 0x30);
            if (!Mem.Write(Buffer, b)) throw new InvalidOperationException("item buffer write failed");
            Mem.Execute(Stub, 0, 5000);
        }

        public void Dispose() { Mem.Dispose(); }
    }
}

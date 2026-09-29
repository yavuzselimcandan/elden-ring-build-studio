// Catalog index, name normalisation, fuzzy search and item-string parsing.
// Compiled at runtime by PowerShell 5.1 (Add-Type, C# 5): keep to C# 5 syntax.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace ERBS
{
    public sealed class CatalogEntry
    {
        public string Category;
        public long ItemId;
        public string Name;
        public string Norm;
        public string[] Tokens;
        public string WeaponClass;   // weapons only, derived from the ID range
        public bool HasAffinities;   // weapons only: catalog carries infused variants
        public long BaseId;          // weapons only: ID with the affinity digits removed
    }

    public sealed class Candidate
    {
        public CatalogEntry Entry;
        public double Score;
        public string Method;
        public override string ToString() { return Entry.Name + " [" + Entry.Category + " " + Entry.ItemId + "] " + Score.ToString("0.00", CultureInfo.InvariantCulture); }
    }

    public sealed class ParsedItem
    {
        public string Name;
        public string Category;
        public int? Upgrade;
        public string AshOfWar;
        public string Affinity;
        public int? Quantity;
        public string Slot;
        public bool LooksLikeNote;
    }

    public static class Text
    {
        public static readonly string[] Affinities = { "Heavy", "Keen", "Quality", "Fire", "Flame Art", "Lightning", "Sacred", "Magic", "Cold", "Poison", "Blood", "Occult" };

        public static string StripDiacritics(string s)
        {
            var d = s.Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder(d.Length);
            foreach (var c in d) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
            return sb.ToString().Normalize(NormalizationForm.FormC);
        }

        // Canonical comparison key: case/diacritic/punctuation insensitive.
        public static string Normalize(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return "";
            s = StripDiacritics(s).ToLowerInvariant();
            s = s.Replace('’', '\'').Replace('‘', '\'').Replace('`', '\'').Replace('´', '\'');
            s = s.Replace("&", " and ");
            s = Regex.Replace(s, @"^ash of war\s*:\s*", "");
            s = s.Replace("'", "");
            s = Regex.Replace(s, @"[^a-z0-9+]+", " ");
            return Regex.Replace(s, @"\s+", " ").Trim();
        }

        public static string Singular(string norm)
        {
            var parts = norm.Split(' ');
            for (int i = 0; i < parts.Length; i++)
            {
                var p = parts[i];
                if (p.Length > 3 && p.EndsWith("s") && !p.EndsWith("ss") && !p.EndsWith("us") && !p.EndsWith("is")) parts[i] = p.Substring(0, p.Length - 1);
            }
            return string.Join(" ", parts);
        }

        public static int Levenshtein(string a, string b)
        {
            if (a.Length == 0) return b.Length;
            if (b.Length == 0) return a.Length;
            var prev = new int[b.Length + 1];
            var cur = new int[b.Length + 1];
            for (int j = 0; j <= b.Length; j++) prev[j] = j;
            for (int i = 1; i <= a.Length; i++)
            {
                cur[0] = i;
                for (int j = 1; j <= b.Length; j++)
                {
                    int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                    cur[j] = Math.Min(Math.Min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
                }
                var t = prev; prev = cur; cur = t;
            }
            return prev[b.Length];
        }

        public static double Ratio(string a, string b)
        {
            int max = Math.Max(a.Length, b.Length);
            return max == 0 ? 1.0 : 1.0 - (double)Levenshtein(a, b) / max;
        }

        // Token-set similarity: each query token is matched to its closest catalog token.
        public static double TokenScore(string[] query, string[] target)
        {
            if (query.Length == 0 || target.Length == 0) return 0;
            double sum = 0;
            foreach (var q in query)
            {
                double best = 0;
                foreach (var t in target)
                {
                    double r = q == t ? 1.0 : (t.StartsWith(q) && q.Length >= 3 ? 0.9 : Math.Pow(Ratio(q, t), 2));
                    if (r > best) best = r;
                }
                sum += best;
            }
            double coverage = sum / query.Length;
            double lengthPenalty = Math.Min(1.0, (double)query.Length / target.Length);
            return coverage * (0.75 + 0.25 * lengthPenalty);
        }
    }

    public sealed class CatalogIndex
    {
        public readonly List<CatalogEntry> Entries = new List<CatalogEntry>();
        readonly Dictionary<string, List<CatalogEntry>> byNorm = new Dictionary<string, List<CatalogEntry>>();
        readonly Dictionary<string, List<CatalogEntry>> bySingular = new Dictionary<string, List<CatalogEntry>>();
        readonly Dictionary<long, CatalogEntry> weaponsById = new Dictionary<long, CatalogEntry>();
        readonly Dictionary<string, string> aliases = new Dictionary<string, string>();

        public CatalogIndex(string[] categories, long[] ids, string[] names)
        {
            for (int i = 0; i < names.Length; i++)
            {
                var e = new CatalogEntry { Category = categories[i], ItemId = ids[i], Name = names[i] };
                e.Norm = Text.Normalize(e.Name);
                e.Tokens = e.Norm.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                Entries.Add(e);
                Add(byNorm, e.Norm, e);
                Add(bySingular, Text.Singular(e.Norm), e);
                if (e.Category == "weapon")
                {
                    e.BaseId = e.ItemId / 10000 * 10000;
                    e.WeaponClass = WeaponClassOf(e.ItemId);
                    weaponsById[e.ItemId] = e;
                }
            }
            foreach (var e in Entries)
                if (e.Category == "weapon") e.HasAffinities = weaponsById.ContainsKey(e.BaseId + 100);
        }

        static void Add(Dictionary<string, List<CatalogEntry>> d, string key, CatalogEntry e)
        {
            List<CatalogEntry> list;
            if (!d.TryGetValue(key, out list)) { list = new List<CatalogEntry>(); d[key] = list; }
            list.Add(e);
        }

        public void AddAlias(string alias, string canonical) { aliases[Text.Normalize(alias)] = Text.Normalize(canonical); }

        public static string WeaponClassOf(long id)
        {
            long c = id / 1000000;
            if (c == 24) return "torch";
            if ((c >= 30 && c <= 32) || c == 62) return "shield";
            if (c == 33) return "staff";
            if (c == 34) return "seal";
            if (c >= 40 && c <= 44) return "bow";
            if (c == 50 || c == 51) return "arrow";
            if (c == 52 || c == 53) return "bolt";
            return "melee";
        }

        public CatalogEntry WeaponById(long id) { CatalogEntry e; return weaponsById.TryGetValue(id, out e) ? e : null; }

        static IEnumerable<CatalogEntry> InCategory(IEnumerable<CatalogEntry> list, string category)
        {
            return string.IsNullOrEmpty(category) ? list : list.Where(x => x.Category == category);
        }

        // Exact lookups in decreasing strictness. Returns the matching entries and the method used.
        public List<CatalogEntry> Exact(string name, string category, out string method)
        {
            method = null;
            var norm = Text.Normalize(name);
            if (norm.Length == 0) return new List<CatalogEntry>();
            string aliased;
            if (aliases.TryGetValue(norm, out aliased)) norm = aliased;
            List<CatalogEntry> list;
            if (byNorm.TryGetValue(norm, out list))
            {
                var inCat = InCategory(list, category).ToList();
                if (inCat.Count > 0) { method = "exact"; return inCat; }
                method = "category-corrected"; return list;
            }
            var sing = Text.Singular(norm);
            if (bySingular.TryGetValue(sing, out list))
            {
                var inCat = InCategory(list, category).ToList();
                if (inCat.Count > 0) { method = "plural"; return inCat; }
                method = "category-corrected"; return list;
            }
            return new List<CatalogEntry>();
        }

        // Ranked fuzzy search used by both the resolver and the UI picker.
        public Candidate[] Search(string query, string category, int max)
        {
            var norm = Text.Normalize(query);
            if (norm.Length == 0) return new Candidate[0];
            var qTokens = norm.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            var results = new List<Candidate>();
            foreach (var e in Entries)
            {
                if (!string.IsNullOrEmpty(category) && e.Category != category) continue;
                double score; string method;
                if (e.Norm == norm) { score = 1.0; method = "exact"; }
                else if (e.Norm.StartsWith(norm)) { score = 0.96 - Math.Min(0.1, (e.Norm.Length - norm.Length) * 0.002); method = "prefix"; }
                else if ((" " + e.Norm).Contains(" " + norm)) { score = 0.92 - Math.Min(0.1, (e.Norm.Length - norm.Length) * 0.002); method = "word"; }
                else
                {
                    double whole = Text.Ratio(norm, e.Norm);
                    double tokens = Text.TokenScore(qTokens, e.Tokens);
                    score = Math.Max(whole, 0.3 * whole + 0.7 * tokens);
                    method = "fuzzy";
                    if (score < 0.5) continue;
                }
                results.Add(new Candidate { Entry = e, Score = score, Method = method });
            }
            // Stable order: score, then shorter names (base items before variants), then lower IDs.
            return results.OrderByDescending(c => c.Score).ThenBy(c => c.Entry.Name.Length).ThenBy(c => c.Entry.ItemId).Take(max).ToArray();
        }
    }

    public static class ItemParser
    {
        static readonly Regex Upgrade = new Regex(@"\s*\+\s*(\d{1,2})\s*$");
        static readonly Regex AshParen = new Regex(@"\s*[\(\[]\s*(?:ash of war|aow|skill)\s*:\s*([^\)\]]+)[\)\]]\s*", RegexOptions.IgnoreCase);
        static readonly Regex AshPipe = new Regex(@"\s*\|\s*(?:ash of war\s*:\s*)?(.+)$", RegexOptions.IgnoreCase);
        static readonly Regex Qty = new Regex(@"\s*(?:[\(\[]\s*)?[x×]\s*(\d{1,3})\s*(?:[\)\]])?\s*$|^\s*(\d{1,3})\s*[x×]\s+", RegexOptions.IgnoreCase);
        static readonly Regex SlotPrefix = new Regex(@"^(head|helm|chest|body|arms|hands|gauntlets|legs|greaves)\s*:\s*", RegexOptions.IgnoreCase);

        public static ParsedItem Parse(string raw, string category)
        {
            var p = new ParsedItem { Category = (category ?? "").Trim().ToLowerInvariant() };
            var s = (raw ?? "").Trim();
            if (p.Category == "spell" || p.Category == "spells" || p.Category == "material" || p.Category == "consumable" || p.Category == "incantation" || p.Category == "sorcery") p.Category = "goods";
            if (p.Category == "weapons") p.Category = "weapon";
            if (p.Category == "talismans") p.Category = "talisman";

            var sm = SlotPrefix.Match(s);
            if (sm.Success)
            {
                var k = sm.Groups[1].Value.ToLowerInvariant();
                p.Slot = k == "head" || k == "helm" ? "Head" : k == "chest" || k == "body" ? "Chest" : k == "legs" || k == "greaves" ? "Legs" : "Arms";
                s = s.Substring(sm.Length);
            }
            var am = AshParen.Match(s);
            if (am.Success) { p.AshOfWar = am.Groups[1].Value.Trim(); s = s.Remove(am.Index, am.Length).Trim(); }
            else
            {
                var pm = AshPipe.Match(s);
                if (pm.Success) { p.AshOfWar = pm.Groups[1].Value.Trim(); s = s.Substring(0, pm.Index).Trim(); }
            }
            var qm = Qty.Match(s);
            if (qm.Success)
            {
                p.Quantity = int.Parse(qm.Groups[1].Success && qm.Groups[1].Value.Length > 0 ? qm.Groups[1].Value : qm.Groups[2].Value);
                s = s.Remove(qm.Index, qm.Length).Trim();
            }
            // Flask upgrades (+N) are part of the goods name; only weapons carry a separate upgrade level.
            if (p.Category == "weapon")
            {
                var um = Upgrade.Match(s);
                if (um.Success) { p.Upgrade = int.Parse(um.Groups[1].Value); s = s.Substring(0, um.Index).Trim(); }
            }
            // "Claymore (Heavy)" / "Claymore [Heavy]" -> "Heavy Claymore"
            var aff = Regex.Match(s, @"^(.*?)\s*[\(\[]\s*(" + string.Join("|", Text.Affinities.Select(Regex.Escape)) + @")(?:\s+affinity)?\s*[\)\]]\s*$", RegexOptions.IgnoreCase);
            if (aff.Success)
            {
                p.Affinity = Text.Affinities.First(a => string.Equals(a, aff.Groups[2].Value, StringComparison.OrdinalIgnoreCase));
                s = aff.Groups[1].Value.Trim();
            }
            p.LooksLikeNote = s.Length > 64 || Regex.IsMatch(s, @"\s/\s|\b(situational|optional|alternatively|recommended|e\.g\.|such as)\b", RegexOptions.IgnoreCase);
            p.Name = s;
            return p;
        }

        // "Wondrous Physick: A + B" -> [A, B]; otherwise empty.
        public static string[] SplitPhysick(string name)
        {
            var m = Regex.Match(name ?? "", @"^\s*(?:flask of\s+)?wondrous physick\s*[:\-]\s*(.+?)\s*(?:\+|&|,|\band\b)\s*(.+?)\s*$", RegexOptions.IgnoreCase);
            return m.Success ? new[] { m.Groups[1].Value.Trim(), m.Groups[2].Value.Trim() } : new string[0];
        }
    }
}

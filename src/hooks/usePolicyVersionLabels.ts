// The name a person gave each policy version a list of runs names ("s, S 24"), by
// version id — so a run row can say which policy it ran under without the page
// holding the whole version list. An unnamed version falls back to its code
// ("Policy 20261004", `policyRef`'s wording, never computed here). Same read and
// the same pre-`20261004000002` fallback as `useModelVersionRefs`.
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { policyRef, stripLegacyDate } from "@/lib/versions/versionLabels";

type Row = { id: string; label?: string | null; version_no?: number | null; version_code?: string | null };

export function usePolicyVersionLabels(ids: Array<string | null | undefined>): Record<string, string> {
  const [labels, setLabels] = useState<Record<string, string>>({});
  const wanted = useMemo(() => [...new Set(ids.filter((i): i is string => !!i))].sort(), [ids]);
  const key = wanted.join("|");

  useEffect(() => {
    if (wanted.length === 0) return;
    let alive = true;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sb = supabase as any;
    void (async () => {
      let res = await sb.from("policy_versions").select("id,label,version_no,version_code").in("id", wanted);
      // Before `20261004000002` there is no code column: the number alone.
      if (res.error) res = await sb.from("policy_versions").select("id,label,version_no").in("id", wanted);
      if (!alive || res.error || !Array.isArray(res.data)) return;
      const next: Record<string, string> = {};
      for (const r of res.data as Row[]) {
        const label = (r.label ? stripLegacyDate(r.label) : "") || policyRef(r);
        if (label) next[r.id] = label;
      }
      setLabels((prev) => ({ ...prev, ...next }));
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return labels;
}

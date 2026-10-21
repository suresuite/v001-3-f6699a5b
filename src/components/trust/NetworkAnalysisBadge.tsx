import { Badge } from "@/components/ui/badge";
import type { StoredState } from "@/lib/network/storedMetrics";

export type NetworkAnalysisState = StoredState | "loading" | "unavailable" | "in progress";

// The verdict belongs to the analysis displayed by this lens (PLAN.md §4 D312).
// A project-wide roll-up cannot answer this question.
const APPEARANCE: Record<NetworkAnalysisState, { label: string; title: string; className: string }> = {
  current: {
    label: "Analysis current",
    title: "The stored analysis matches this network's current inputs.",
    className: "border-emerald-500 text-emerald-700",
  },
  stale: {
    label: "Analysis needs recalculation",
    title: "The stored analysis was computed for an earlier version of this network. Recalculate the analysis to update it.",
    className: "border-amber-500 text-amber-700",
  },
  unknown: {
    label: "Analysis provenance unknown",
    title: "The stored figures do not identify their inputs. Recalculate the analysis to record their provenance.",
    className: "border-slate-400 text-slate-600",
  },
  missing: {
    label: "No stored analysis",
    title: "No stored analysis is available for this network.",
    className: "border-slate-300 text-slate-500",
  },
  loading: {
    label: "Checking analysis…",
    title: "Reading the analysis for this network.",
    className: "border-slate-300 text-slate-500",
  },
  unavailable: {
    label: "Analysis status unavailable",
    title: "The analysis could not be read. Refresh to try again.",
    className: "border-amber-500 text-amber-700",
  },
  "in progress": {
    label: "Analysis in progress",
    title: "The analysis is still running. Refresh after it completes.",
    className: "border-slate-400 text-slate-600",
  },
};

export function NetworkAnalysisBadge({ state }: { state: NetworkAnalysisState }) {
  const look = APPEARANCE[state];
  return <Badge variant="outline" className={look.className} title={look.title}>{look.label}</Badge>;
}

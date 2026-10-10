// How each page kind is NAMED wherever it is shown: the header pill, the nav
// badge, the landing grid. One table, so the three cannot disagree.

import { Database, HelpCircle, Home, Lightbulb, Workflow, type LucideIcon } from "lucide-react";
import type { DocKind } from "@/components/docs/registry";

export const KIND_LABEL: Record<DocKind, { label: string; short: string; icon: LucideIcon }> = {
  guide: { label: "Guide", short: "guide", icon: Workflow },
  concept: { label: "Concept", short: "concept", icon: Lightbulb },
  reference: { label: "Reference", short: "ref", icon: Database },
  troubleshooting: { label: "Questions", short: "q&a", icon: HelpCircle },
  overview: { label: "Overview", short: "overview", icon: Home },
};

/** The article column's width per kind. Prose inside it still stops at 68ch. */
export const KIND_MAX_WIDTH: Record<DocKind, string> = {
  guide: "max-w-[700px]",
  concept: "max-w-[700px]",
  troubleshooting: "max-w-[700px]",
  reference: "max-w-[920px]",
  overview: "max-w-[880px]",
};

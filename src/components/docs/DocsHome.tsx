// The manual's front door (/docs) — task first (WP 5.2a redesign, §6.4).
//
// A reader arrives with a job, not a section number, so the page opens on
// five tasks, then the four role paths §6.5 says first-time readers come with,
// then the whole site map. Everything is filtered to the sections this reader
// may open (released section by section from /admin/docs), so every card and
// link here lands on a page rather than on "not available to you".
//
// Definition of done for the redesign: "How do I upload my BOM?" takes two
// clicks — Upload data, then the BOM reference from the guide's links.

import { Link } from "react-router-dom";
import {
  ArrowRight, Code2, FlaskConical, SlidersHorizontal, TrendingUp, Upload, type LucideIcon,
} from "lucide-react";
import { DOC_GROUPS, getPage } from "@/components/docs/registry";
import { KIND_LABEL } from "@/components/docs/docKinds";
import { useCapabilities } from "@/hooks/useCapabilities";

const TASKS: { slug: string; icon: LucideIcon; label: string; sub: string }[] = [
  { slug: "uploading-data", icon: Upload, label: "Upload data", sub: "Get your CSVs into a project, check what changed, accept the rows." },
  { slug: "how-policies-work", icon: SlidersHorizontal, label: "Set policies", sub: "Decide how the chain reorders, sources and produces." },
  { slug: "simulation-lab", icon: FlaskConical, label: "Run a simulation", sub: "Run a scenario — with or without a disruption." },
  { slug: "reading-your-results", icon: TrendingUp, label: "Read results", sub: "Check the run, then read service, cost and uncertainty." },
  { slug: "getting-an-api-key", icon: Code2, label: "Use the API", sub: "Create a scoped key and make your first request." },
];

/** The four role paths §6.5 says every first-time reader arrives with. */
const ROLES: { slug: string; label: string; fragment?: string }[] = [
  { slug: "what-suresuite-is", label: "Manager or researcher" },
  { slug: "your-first-project", label: "Analyst" },
  { slug: "how-suresuite-is-designed", label: "Engineer", fragment: "engineer" },
  { slug: "getting-an-api-key", label: "API developer" },
];

/**
 * The three pages each section leads with on the front door. An editorial
 * choice — what a newcomer to the section should open first — so it is named
 * here; a section not listed shows its first three pages.
 */
const TOP_PAGES: Record<string, string[]> = {
  overview: ["what-suresuite-is", "how-your-data-flows", "known-limits"],
  "getting-started": ["your-first-project", "uploading-data", "projects"],
  "input-tables": ["inbound-logistics", "bom-single-level", "materials"],
  policies: ["how-policies-work", "policy-types", "when-a-value-is-missing"],
  experiments: ["simulation-lab", "disruptions", "stress-tests"],
  results: ["reading-your-results", "kpis-and-resilience-index", "per-item-time-series"],
  reference: ["glossary", "all-tables", "field-index"],
};

export default function DocsHome() {
  const { docs } = useCapabilities();
  const groups = DOC_GROUPS.filter((g) => docs.canReadSection(g.key));
  const visible = (slug: string) => {
    const page = getPage(slug);
    return Boolean(page && page.status === "live" && docs.canReadSection(page.sectionKey));
  };
  const tasks = TASKS.filter((t) => visible(t.slug));
  const roles = ROLES.filter((r) => visible(r.slug));
  const pageCount = groups.reduce((n, g) => n + g.pages.length, 0);

  return (
    <div className="mx-auto max-w-[1040px] space-y-12">
      {/* Hero */}
      <header className="space-y-4">
        <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.2em] text-[var(--brand-red)]">
          <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-[var(--brand-red)]" />
          Documentation
        </div>
        <h1 className="text-[28px] font-semibold leading-[1.1] tracking-[-0.024em] md:text-[38px]">
          What do you want <span className="font-serif font-medium italic">to do?</span>
        </h1>
        <p className="max-w-[60ch] text-[15px] leading-relaxed text-gray-600 md:text-[16px]">
          SuReSuite models your supply chain so you can break it on purpose and compare the cost and
          service of different responses. Pick a task {"—"} every guide starts with the steps.
          You need an approved account to work in a project;{" "}
          <Link to="/auth" className="docs-link">sign in</Link> if you already have one.
        </p>
      </header>

      {/* Tasks */}
      {tasks.length > 0 && (
        <section aria-label="Tasks" className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-3">
          {tasks.map(({ slug, icon: Icon, label, sub }) => (
            <Link
              key={slug}
              to={`/docs/${slug}`}
              className="group flex min-h-[168px] flex-col rounded-lg border border-border bg-card p-4 shadow-xs transition-colors hover:bg-accent"
            >
              <span className="flex h-9 w-9 items-center justify-center rounded-md border border-border bg-background">
                <Icon className="h-[18px] w-[18px]" aria-hidden />
              </span>
              <span className="mt-3 text-[16px] font-semibold text-foreground">{label}</span>
              <span className="mt-1 text-[13.5px] leading-snug text-gray-600">{sub}</span>
              <span className="mt-auto flex items-center gap-1 pt-3 text-[12.5px] text-foreground">
                <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden />
                {getPage(slug)?.title}
              </span>
            </Link>
          ))}
        </section>
      )}

      {/* Roles */}
      {roles.length > 0 && (
        <section aria-label="Start from your role" className="space-y-3">
          <h2 className="text-[14px] font-semibold text-foreground">Or start from your role</h2>
          <div className="flex flex-wrap gap-2">
            {roles.map((r) => (
              <Link
                key={r.label}
                to={`/docs/${r.slug}${r.fragment ? `#${r.fragment}` : ""}`}
                className="inline-flex min-h-11 items-center gap-2 rounded-full border border-border px-4 text-[13.5px] text-foreground transition-colors hover:bg-accent md:min-h-10"
              >
                <span className="font-medium">{r.label}</span>
                <span className="text-gray-600">{"→"} {getPage(r.slug)?.title}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* The whole site map */}
      <section aria-labelledby="browse" className="space-y-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="browse" className="text-[18px] font-semibold tracking-tight">Browse the manual</h2>
          <span className="text-[13px] tabular-nums text-gray-600">
            {pageCount} pages in {groups.length} {groups.length === 1 ? "section" : "sections"}
          </span>
        </div>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(min(100%,300px),1fr))] gap-px overflow-hidden rounded-lg border border-border bg-border">
          {groups.map((g) => {
            const top = (TOP_PAGES[g.key] ?? g.pages.slice(0, 3).map((p) => p.slug))
              .map((s) => g.pages.find((p) => p.slug === s))
              .filter((p): p is NonNullable<typeof p> => Boolean(p));
            const first = g.pages.find((p) => p.status === "live") ?? g.pages[0];
            return (
              <div key={g.key} className="flex flex-col bg-background p-4">
                <span className="font-mono text-[11px] font-semibold tabular-nums text-[var(--brand-red)]">
                  {String(g.section).padStart(2, "0")}
                </span>
                <Link to={`/docs/${first.slug}`} className="mt-1 text-[15px] font-semibold text-foreground hover:underline">
                  {g.group}
                </Link>
                <p className="mt-1 text-[13.5px] leading-snug text-gray-600">{g.blurb}</p>
                <ul className="mt-3 space-y-0.5">
                  {top.map((p) => (
                    <li key={p.slug}>
                      <Link
                        to={`/docs/${p.slug}`}
                        className="flex min-h-11 items-center justify-between gap-3 text-[13.5px] text-foreground hover:underline md:min-h-7"
                      >
                        <span className="min-w-0">{p.title}</span>
                        <span className="font-mono text-[9px] uppercase tracking-[0.1em] text-gray-600">
                          {KIND_LABEL[p.kind].short}
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
                {g.pages.length > top.length && (
                  <Link to={`/docs/${first.slug}`} className="mt-2 inline-flex min-h-11 items-center text-[12.5px] text-gray-600 hover:text-foreground md:min-h-6">
                    + {g.pages.length - top.length} more
                  </Link>
                )}
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}

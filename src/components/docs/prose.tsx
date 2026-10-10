// Presentational primitives for the manual's page bodies.
//
// One set of components, one payload: DocsLayout renders these on a phone and
// on a desktop from the same tree (§6.4 — "mobile reads the same payload"). A
// second content tree for small screens is the duplication this programme
// exists to end, so nothing here branches on device; it branches on width, in
// CSS, at the single `md` breakpoint the UI spec allows.
//
// Headings: DocsLayout's "On this page" rail tracks the article's `h2`s, so
// `Section` renders h2 and takes an explicit `id`. Explicit, because the id is
// the deep link (§6.4) and an id derived from the heading text changes when
// the wording is edited — a stable URL cannot depend on prose.
//
// RHYTHM (WP 5.2a redesign). Spacing between blocks is not set by the blocks.
// Each block declares what it IS — `data-b="text"`, `"check"`, or nothing for a
// visual block (table, figure, callout, steps…) — and `index.css` spaces
// neighbours from the pair: text after text 14px, a check 12px, visual after
// visual 24px, text beside a visual 28px. A body therefore never adds margin,
// and a generated block from `tableRef.tsx` falls into the right gap without
// knowing this file exists. Figure and table numbers are CSS counters for the
// same reason: they count from 1 on every page without a body numbering them.

import { Fragment, ReactNode } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle, CheckCircle2, Check as CheckIcon, ChevronRight, Circle, Clock, Database, Info,
  Layers, Lightbulb, User,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { CONTRACT_VERSION, ENGINE_VERSION } from "@/components/docs/generated/dataModel.generated";
import { getPage } from "@/components/docs/registry";
import { useDocPage, useDocsChrome } from "@/components/docs/docPageContext";
import { KIND_LABEL } from "@/components/docs/docKinds";
import { FROZEN_CELL, FROZEN_CELL_ON_TINT } from "@/components/shared/frozenCell";

/**
 * Render a contract string, turning `backticked` spans into code.
 *
 * The sidecars are authored in prose with markdown code spans — "joins on
 * `organization_members.user_id`" — because they are also rendered into
 * markdown pages under docs/data/tables/. Printing them raw on an HTML page
 * shows the backticks, which reads as a typo in generated text and quietly
 * undermines the thing generated text is for. Nothing else in markdown is
 * interpreted: this is a code-span renderer, not a markdown parser.
 */
export function Prose({ text }: { text: string }) {
  if (!text.includes("`")) return <>{text}</>;
  const parts = text.split(/`([^`]+)`/g);
  return (
    <>
      {parts.map((part, i) =>
        i % 2 === 1 ? (
          <code key={i} className="docs-code">
            {part}
          </code>
        ) : (
          <span key={i}>{part}</span>
        ),
      )}
    </>
  );
}

// ── the page header ─────────────────────────────────────────────────────────

/**
 * The header every page shares: breadcrumb, title, lead, and one meta row.
 *
 * The templates differ BELOW this. Kind, reading time, audience and where the
 * page's facts come from are read from `DocPageContext` — the registry and the
 * generated index — never typed into a body.
 */
export function PageTitle({ children, lead }: { children: ReactNode; lead?: ReactNode }) {
  const meta = useDocPage();
  const { tocButton } = useDocsChrome();
  const page = meta?.page;
  const kind = page ? KIND_LABEL[page.kind] : null;
  const questions = page?.kind === "troubleshooting" ? (meta?.sections ?? []) : [];
  return (
    <>
      <header className="docs-header" data-kind={page?.kind}>
        {page && (
          <nav aria-label="Breadcrumb" className="flex min-w-0 items-center gap-1.5 text-[13px] text-gray-600">
            <Link to="/docs" className="inline-flex min-h-6 shrink-0 items-center hover:text-foreground">Docs</Link>
            <ChevronRight className="h-3.5 w-3.5 shrink-0" aria-hidden />
            <span className="min-h-6 truncate leading-6">{page.group}</span>
          </nav>
        )}
        <h1 className="docs-h1">{children}</h1>
        {lead && <p className="docs-lead">{lead}</p>}
        {page && kind && (
          <div className="mt-1.5 flex flex-wrap items-center gap-x-[18px] gap-y-2 text-[13px] text-gray-600">
            <span className="inline-flex h-6 items-center gap-1.5 rounded-full border border-border px-2.5 text-foreground">
              <kind.icon className="h-3 w-3" aria-hidden />
              {kind.label}
            </span>
            {meta?.minutes != null && (
              <span className="inline-flex items-center gap-1.5">
                <Clock className="h-3.5 w-3.5" aria-hidden />
                {meta.minutes} min read
              </span>
            )}
            <span className="inline-flex items-center gap-1.5">
              <User className="h-3.5 w-3.5" aria-hidden />
              For {page.audience.toLowerCase()}
            </span>
            {page.source && (
              <span className="inline-flex items-center gap-1.5">
                <Database className="h-3.5 w-3.5" aria-hidden />
                Generated from the {page.source === "contract" ? "data contract" : "engine registry"}
              </span>
            )}
          </div>
        )}
      </header>
      {page && tocButton}
      {questions.length > 1 && (
        <nav aria-label="Questions on this page" className="flex flex-wrap gap-2">
          {questions.map((q) => (
            <a
              key={q.id}
              href={`#${q.id}`}
              className="inline-flex min-h-11 items-center rounded-md border border-border px-3 text-[13px] text-foreground transition-colors hover:bg-accent md:min-h-9"
            >
              {q.title}
            </a>
          ))}
        </nav>
      )}
      {meta?.summaryCard}
    </>
  );
}

/** Keep article titles and search summaries in the registry. */
export function DocPageTitle({ slug }: { slug: string }) {
  const page = getPage(slug);
  return <PageTitle lead={page?.summary}>{page?.title}</PageTitle>;
}

// ── sections and text ───────────────────────────────────────────────────────

/** Three short takeaways before the detail, from the same payload at every width. */
export function InShort({ items }: { items: [ReactNode, ReactNode, ReactNode] }) {
  return (
    <aside className="docs-inshort rounded-lg bg-muted px-[18px] py-4" aria-label="In short">
      <div className="docs-kicker">In short</div>
      <ul className="mt-2.5 space-y-2.5">
        {items.map((item, i) => (
          <li key={i} className="grid grid-cols-[15px_minmax(0,1fr)] gap-2.5 text-[14px] leading-[1.55] text-foreground">
            <CheckIcon className="mt-[3px] h-[15px] w-[15px]" aria-hidden />
            <span>{item}</span>
          </li>
        ))}
      </ul>
    </aside>
  );
}

export function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section className="docs-sec" data-related={id === "related" ? "" : undefined}>
      <h2 id={id} className="docs-h2">
        <span className="docs-secnum" aria-hidden />
        <span>{title}</span>
      </h2>
      {children}
    </section>
  );
}

export function P({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <p data-b="text" className={cn("docs-p", className)}>
      {children}
    </p>
  );
}

/** Emphasised sentence that carries the point of the section it opens. */
export function Key({ children }: { children: ReactNode }) {
  return (
    <p data-b="text" className="max-w-[68ch] text-[14.5px] font-semibold leading-[1.55] text-foreground">
      {children}
    </p>
  );
}

export function Bullets({ items }: { items: ReactNode[] }) {
  return (
    <ul data-b="text" className="max-w-[68ch] list-disc space-y-1.5 pl-5 text-[14px] leading-[1.7] text-foreground">
      {items.map((item, i) => (
        <li key={i}>{item}</li>
      ))}
    </ul>
  );
}

export function Term({ children }: { children: ReactNode }) {
  return <code className="docs-code">{children}</code>;
}

// ── callouts ────────────────────────────────────────────────────────────────

/**
 * Four tones, told apart by SHAPE as well as colour — a fill, a hairline, an
 * amber band and a dashed outline — so they survive a projector and a reader
 * who does not see colour. `limit` and `law` are the names eighty-odd bodies
 * already use; they map onto `warning` and `note` rather than being renamed.
 */
type CalloutTone = "tip" | "note" | "warning" | "notsim" | "limit" | "law";

const TONE: Record<"tip" | "note" | "warning" | "notsim", { box: string; icon: typeof Info; iconClass: string; label: string }> = {
  tip: { box: "bg-muted", icon: Lightbulb, iconClass: "text-foreground", label: "Tip" },
  note: { box: "border border-border-strong", icon: Info, iconClass: "text-gray-600", label: "Note" },
  warning: {
    box: "border border-[hsl(var(--status-warn)/0.45)] bg-[hsl(var(--status-warn)/0.1)]",
    icon: AlertTriangle,
    iconClass: "text-[hsl(var(--status-warn))]",
    label: "Limit",
  },
  notsim: {
    box: "border-[1.5px] border-dashed border-muted-foreground/70",
    icon: Circle,
    iconClass: "text-gray-600",
    label: "The simulation doesn't use every field",
  },
};

export function Callout({
  tone = "note",
  title,
  children,
}: {
  tone?: CalloutTone;
  title?: string;
  children: ReactNode;
}) {
  const key = tone === "limit" ? "warning" : tone === "law" ? "note" : tone;
  const t = TONE[key];
  const Icon = t.icon;
  return (
    <aside
      role="note"
      data-tone={key}
      className={cn("grid grid-cols-[18px_minmax(0,1fr)] gap-3 rounded-lg px-4 py-3.5", t.box)}
    >
      <Icon className={cn("mt-[2px] h-[18px] w-[18px]", t.iconClass)} aria-hidden />
      <div className="min-w-0">
        <div className="text-[14px] font-semibold leading-snug text-foreground">
          {title ?? (tone === "law" ? "The rule" : t.label)}
        </div>
        <div className="docs-callout-body mt-[3px] space-y-2 text-[13.5px] leading-[1.6] text-foreground">
          {children}
        </div>
      </div>
    </aside>
  );
}

/** "You should see …" — the checkpoint a task step ends on. The lead-in is fixed copy. */
export function Check({ children }: { children: ReactNode }) {
  return (
    <div
      data-b="check"
      className="grid grid-cols-[15px_minmax(0,1fr)] gap-2.5 rounded-md border border-[hsl(var(--status-ok)/0.3)] bg-[hsl(var(--status-ok)/0.08)] px-3.5 py-2.5"
    >
      <CheckCircle2 className="mt-[3px] h-[15px] w-[15px] text-[hsl(var(--status-ok))]" aria-hidden />
      <p className="text-[15px] leading-[1.55] text-foreground">
        <strong className="font-semibold">You should see</strong> {children}
      </p>
    </div>
  );
}

// ── structured blocks ───────────────────────────────────────────────────────

/** A numbered walkthrough. Each step names the screen it happens on. */
export function Steps({
  steps,
}: {
  steps: { title: string; where?: string; body: ReactNode; check?: ReactNode }[];
}) {
  return (
    <ol className="space-y-[22px]">
      {steps.map((s, i) => (
        <li key={s.title} className="relative grid grid-cols-[24px_minmax(0,1fr)] gap-3.5">
          {i < steps.length - 1 && (
            <span aria-hidden className="absolute bottom-[-22px] left-[11.5px] top-7 w-px bg-border" />
          )}
          <span className="flex h-6 w-6 items-center justify-center rounded-full border-[1.5px] border-foreground bg-background text-[12px] font-semibold tabular-nums text-foreground">
            {i + 1}
          </span>
          <div className="min-w-0 space-y-1.5">
            <div className="flex flex-wrap items-center gap-2 pt-[1px]">
              <span className="text-[15.5px] font-semibold leading-snug text-foreground">{s.title}</span>
              {s.where && (
                <span className="rounded-[3px] bg-muted px-[7px] py-[2px] font-mono text-[10.5px] text-gray-700">
                  {s.where}
                </span>
              )}
            </div>
            <div className="max-w-[68ch] text-[14px] leading-[1.7] text-foreground">{s.body}</div>
            {s.check && <Check>{s.check}</Check>}
          </div>
        </li>
      ))}
    </ol>
  );
}

/** Term-and-meaning pairs. Stacks on a phone, two columns from `md`. */
export function Defs({ items }: { items: { term: ReactNode; def: ReactNode }[] }) {
  return (
    <dl className="divide-y divide-[--hair-divider] rounded-lg border border-border">
      {items.map((d, i) => (
        <div key={i} className="grid grid-cols-1 gap-1 px-4 py-3 md:grid-cols-[11rem_minmax(0,1fr)] md:gap-6">
          <dt className="text-[14px] font-semibold text-foreground">{d.term}</dt>
          <dd className="min-w-0 text-[13.5px] leading-[1.6] text-gray-600">{d.def}</dd>
        </div>
      ))}
    </dl>
  );
}

/** Questions answered in place — a guide's "If something goes wrong". */
export function QA({ items }: { items: { q: ReactNode; a: ReactNode }[] }) {
  return (
    <dl className="divide-y divide-[--hair-divider] rounded-lg border border-border">
      {items.map((x, i) => (
        <div key={i} className="px-4 py-3">
          <dt className="text-[14px] font-semibold text-foreground">{x.q}</dt>
          <dd className="mt-1 max-w-[68ch] text-[13.5px] leading-[1.6] text-gray-600">{x.a}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * "How this works" — reasoning and notation the task does not need, collapsed.
 * A native `<details>`, so it opens without JavaScript and in the body tests.
 */
export function Details({ title, children }: { title: string; children: ReactNode }) {
  return (
    <details className="docs-details group rounded-lg border border-border">
      <summary className="flex min-h-[50px] cursor-pointer list-none items-center gap-2.5 px-4 text-[14px] font-medium text-foreground [&::-webkit-details-marker]:hidden">
        <Layers className="h-4 w-4 text-gray-600" aria-hidden />
        <span className="min-w-0 flex-1">{title}</span>
        <ChevronRight className="h-4 w-4 text-gray-600 transition-transform duration-200 group-open:rotate-90 motion-reduce:transition-none" aria-hidden />
      </summary>
      <div className="space-y-2 px-4 pb-4 pt-0.5 text-[13.5px] leading-[1.6] text-gray-600">{children}</div>
    </details>
  );
}

/** A ledger table with a numbered caption above it. Scrolls inside its shell. */
export function DocTable({
  caption,
  head,
  rows,
}: {
  caption?: string;
  head: string[];
  rows: ReactNode[][];
}) {
  return (
    <div className="docs-table space-y-2.5" data-captioned={caption ? "" : undefined}>
      {caption && (
        <div className="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
          <span className="docs-label docs-label-table" aria-hidden />
          <span className="text-[13px] text-gray-600">{caption}</span>
        </div>
      )}
      <div className="overflow-x-auto rounded-sm border border-[--hair-border]">
        <table className="w-full border-collapse text-left">
          <thead>
            <tr>
              {head.map((h, j) => (
                <th
                  key={h}
                  scope="col"
                  className={cn(
                    "whitespace-nowrap bg-[--hair-th] px-4 py-2 font-mono text-[11px] font-medium uppercase tracking-[0.04em] text-[--ledger-quiet]",
                    // §2.7: the first column names the row; it stays put when a phone scrolls sideways.
                    j === 0 && FROZEN_CELL_ON_TINT,
                  )}
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i} className="hover:bg-[--hair-row-hover]">
                {r.map((cell, j) => (
                  <td
                    key={j}
                    className={cn(
                      "border-t border-[--hair-divider] px-4 py-2.5 align-top text-[13px] leading-[1.5] tabular-nums text-foreground",
                      j === 0 && cn("font-medium", FROZEN_CELL),
                    )}
                  >
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/**
 * A row of steps drawn as cards — a sequence the reader should see as one.
 * HTML rather than an SVG, so it reflows: arrows run across from `md`, and the
 * cards stack with a down arrow below it. Counted as a figure.
 */
export function Flow({
  caption,
  items,
  highlight,
}: {
  caption: string;
  items: { kicker?: string; title: string; detail: string }[];
  highlight?: number;
}) {
  return (
    <figure className="docs-flow space-y-3">
      <div
        className="grid grid-cols-1 items-stretch gap-y-1 md:gap-x-0 md:[grid-template-columns:var(--flow-cols)]"
        style={{ ["--flow-cols" as string]: items.map((_, i) => (i ? "18px minmax(0,1fr)" : "minmax(0,1fr)")).join(" ") }}
      >
        {items.map((it, i) => (
          <Fragment key={it.title}>
            {i > 0 && (
              <span aria-hidden className="flex items-center justify-center text-[14px] text-gray-600">
                <span className="md:hidden">{"↓"}</span>
                <span className="hidden md:inline">{"→"}</span>
              </span>
            )}
            <div
              className={cn(
                "rounded-md border px-[13px] py-3",
                i === highlight ? "border-foreground bg-muted" : "border-border",
              )}
            >
              {it.kicker && <div className="docs-kicker">{it.kicker}</div>}
              <div className="text-[13px] font-semibold text-foreground">{it.title}</div>
              <div className="text-[12px] leading-snug text-gray-600">{it.detail}</div>
            </div>
          </Fragment>
        ))}
      </div>
      <figcaption className="flex flex-wrap items-baseline gap-x-2.5 gap-y-1 text-[13.5px] leading-[1.6] text-gray-600">
        <span className="docs-label docs-label-figure" aria-hidden />
        <span>{caption}</span>
      </figcaption>
    </figure>
  );
}

/** A handful of headline numbers — what a guide's example is made of. */
export function Stats({ items }: { items: [string, string][] }) {
  return (
    // Flex, not grid: a wrapped last row stretches to the edge instead of
    // leaving an empty cell showing the hairline colour behind it.
    <dl className="flex flex-wrap gap-px overflow-hidden rounded-lg border border-border bg-border">
      {items.map(([k, v]) => (
        <div key={k} className="min-w-[110px] flex-1 bg-background px-3.5 py-3">
          <dt className="docs-kicker">{k}</dt>
          <dd className="mt-1 text-[16px] font-semibold tabular-nums text-foreground">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/** A code sample. Scrolls sideways rather than wrapping a command. */
export function Code({ children }: { children: string }) {
  return (
    <pre className="overflow-x-auto rounded-md border border-border bg-muted px-4 py-3.5 font-mono text-[13px] leading-[1.6] text-foreground">
      <code>{children}</code>
    </pre>
  );
}

export function Figure({
  caption,
  children,
}: {
  caption: string;
  children: ReactNode;
}) {
  return (
    <figure className="space-y-3">
      <div className="overflow-x-auto rounded-lg border border-border bg-card px-6 py-7">{children}</div>
      <figcaption className="flex flex-wrap items-baseline gap-x-2.5 gap-y-1 text-[13.5px] leading-[1.6] text-gray-600">
        <span className="docs-label docs-label-figure" aria-hidden />
        <span>{caption}</span>
      </figcaption>
    </figure>
  );
}

/** Pages to read next, as cards: title and the page's own summary. */
export function RelatedCards({ slugs }: { slugs: string[] }) {
  const pages = slugs.map((s) => getPage(s)).filter((p): p is NonNullable<typeof p> => Boolean(p));
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(220px,1fr))] gap-2.5">
      {pages.map((p) => (
        <Link
          key={p.slug}
          to={`/docs/${p.slug}`}
          className="block min-h-14 rounded-lg border border-border px-3.5 py-3 transition-colors hover:bg-accent"
        >
          <div className="text-[14px] font-semibold text-foreground">{p.title}</div>
          {p.summary && <div className="mt-0.5 text-[12.5px] leading-snug text-gray-600">{p.summary}</div>}
        </Link>
      ))}
    </div>
  );
}

// ── links ───────────────────────────────────────────────────────────────────

/** Link to another page of the manual. */
export function DocLink({ to, children }: { to: string; children: ReactNode }) {
  return (
    <Link to={`/docs/${to}`} className="docs-link">
      {children}
    </Link>
  );
}

/** Link to a screen in the product. */
export function AppLink({ to, children }: { to: string; children: ReactNode }) {
  return (
    <Link to={to} className="docs-link">
      {children}
    </Link>
  );
}

/**
 * The provenance footer every generated page carries (§6.4).
 *
 * It names the contract version, never a date. A committed generated file that
 * embeds today's date differs from itself tomorrow, so the drift gate fails on
 * every pull request for a reason no change caused — and a gate that cries wolf
 * is the gate people route around. (Corrected in WP 1.4; the rule used to say
 * "generated on date Z".)
 */
export function Provenance({ from: _from }: { from: string }) {
  return (
    <div className="flex items-start gap-2 border-t border-border pt-4 text-[12.5px] leading-[1.6] text-gray-600">
      <Database className="mt-[3px] h-[13px] w-[13px] shrink-0" aria-hidden />
      <p>
        Reference data: contract <span className="font-mono">{CONTRACT_VERSION}</span>, engine{" "}
        <span className="font-mono">{ENGINE_VERSION}</span>. Generated definitions are checked
        separately from this page&rsquo;s explanatory guidance.
      </p>
    </div>
  );
}

// Dedicated, full-screen documentation chrome for the /docs manual — modelled
// on a classic three-pane docs layout: a sticky toolbar (search · text size ·
// reading progress), a collapsible left nav tree, the article, and a right
// "On this page" + "Related" rail. No app shell.
//
// Page bodies arrive through <Outlet/>; `registry.ts` owns the site map and
// `DocPage.tsx` resolves a slug to a body or to a stub. WP 5.2a restored the
// routes, moved the manual to /docs (PLAN.md §6 names it that throughout; the
// old address still redirects so no existing link breaks) and taught the nav
// and the search to show a page that is planned but not yet written.
//
// REDESIGN (WP 5.2a, §6.4). Three panes from `lg` — the one sanctioned second
// breakpoint, spec §6.1 — and one column below it, where the nav becomes a left
// sheet and "On this page" a bottom sheet opened from a button under the page
// header. The handoff drew the switch at 1100px; it is `lg` (1024px) here
// because a breakpoint the spec does not name is a breakpoint the audit would
// rightly refuse. There is no theme toggle: the product is light-locked
// (`forcedTheme` in App.tsx), and a dark manual beside a light app is a second
// design nobody has drawn the hairline tokens for.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { useAuth } from "@/hooks/useAuth";
import { useCapabilities } from "@/hooks/useCapabilities";
import { DocsReaderContext } from "@/components/docs/docsReader";
import { DocsChromeContext } from "@/components/docs/docPageContext";
import { KIND_LABEL, KIND_MAX_WIDTH } from "@/components/docs/docKinds";
import { DOCS_INDEX } from "@/components/docs/generated/docsIndex.generated";
import {
  Search, ChevronRight, ArrowLeft, ArrowRight, X, PanelLeftOpen, BookOpen, ListTree,
} from "lucide-react";
import {
  DEFAULT_SLUG, DOC_GROUPS, DOC_SEARCH_FALLBACK, getPage, prevNext, searchPages, searchSections,
} from "@/components/docs/registry";

const FONT_STEPS = [0.92, 1, 1.12];
const FONT_KEY = "docs.textScale";
/** The key this control used before the redesign, read once so a reader keeps their size. */
const OLD_FONT_KEY = "docs-font-step";

const SECTIONS_BY_SLUG = Object.fromEntries(
  Object.entries(DOCS_INDEX).map(([slug, e]) => [slug, e.sections]),
);

function slugify(s: string) {
  return (
    s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "").slice(0, 60) ||
    "section"
  );
}

type Heading = { id: string; text: string };

/**
 * The article's section headings, the one the reader is in, and how far down
 * the page they are.
 *
 * "The one they are in" is the LAST heading whose top has passed 140px from
 * the viewport top — a scroll listener rather than an IntersectionObserver,
 * because "last one above a line" is a question about every heading at once,
 * and the observer only reports the ones that just crossed.
 */
function useReading(ref: React.RefObject<HTMLElement>, dep: string) {
  const [headings, setHeadings] = useState<Heading[]>([]);
  const [active, setActive] = useState(0);
  const [pct, setPct] = useState(0);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const collect = () => {
      const els = Array.from(root.querySelectorAll(".docs-article h2")) as HTMLElement[];
      const used = new Set<string>();
      return els.map((el) => {
        let id = el.id;
        if (!id) {
          const base = slugify(el.textContent || "section");
          let candidate = base;
          let n = 2;
          while (used.has(candidate)) candidate = `${base}-${n++}`;
          id = candidate;
          el.id = id;
        }
        used.add(id);
        return { id, text: (el.textContent || "").trim() };
      });
    };
    let list = collect();
    setHeadings(list);
    setActive(0);
    // A body that loads its content (Q&A, the engine versions) renders its
    // headings after the first paint; pick them up when the article changes.
    const mo = new MutationObserver(() => {
      const next = collect();
      if (next.map((h) => h.id).join() !== list.map((h) => h.id).join()) {
        list = next;
        setHeadings(next);
      }
    });
    mo.observe(root, { childList: true, subtree: true });

    let frame = 0;
    const measure = () => {
      frame = 0;
      let a = 0;
      list.forEach((h, i) => {
        const el = document.getElementById(h.id);
        if (el && el.getBoundingClientRect().top < 140) a = i;
      });
      const max = document.documentElement.scrollHeight - window.innerHeight;
      setActive(a);
      setPct(max > 0 ? Math.min(100, Math.round((100 * window.scrollY) / max)) : 0);
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(measure);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    measure();
    return () => {
      mo.disconnect();
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, [ref, dep]);

  return { headings, active: Math.min(active, Math.max(0, headings.length - 1)), pct };
}

function FontSizeControl({
  step,
  setStep,
}: {
  step: number;
  setStep: (n: number) => void;
}) {
  return (
    <div className="hidden items-center rounded-md border border-border bg-background md:flex" role="group" aria-label="Text size">
      <button
        type="button"
        className="flex h-[34px] w-[34px] items-center justify-center text-[12px] text-gray-600 hover:text-foreground disabled:opacity-40"
        aria-label="Smaller text"
        title="Smaller text"
        disabled={step <= 0}
        onClick={() => setStep(Math.max(0, step - 1))}
      >
        A
      </button>
      <span className="h-4 w-px bg-border" />
      <button
        type="button"
        className="flex h-[34px] w-[34px] items-center justify-center text-[16px] text-gray-600 hover:text-foreground disabled:opacity-40"
        aria-label="Larger text"
        title="Larger text"
        disabled={step >= FONT_STEPS.length - 1}
        onClick={() => setStep(Math.min(FONT_STEPS.length - 1, step + 1))}
      >
        A
      </button>
    </div>
  );
}

function DocsSearch() {
  const navigate = useNavigate();
  const { docs } = useCapabilities();
  const [q, setQ] = useState("");
  const [focused, setFocused] = useState(false);
  const [sel, setSel] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  // Only sections this reader may open: a result that lands on "not available
  // to you" is a result that should not have been offered.
  const results = useMemo(() => searchPages(q, docs.canReadSection), [q, docs.canReadSection]);
  const inside = useMemo(
    () => searchSections(q, SECTIONS_BY_SLUG, docs.canReadSection),
    [q, docs.canReadSection],
  );
  const open = focused && q.trim().length > 0;

  // "/" focuses the search from anywhere on the page, unless the reader is
  // already typing into something.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey) return;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
      e.preventDefault();
      inputRef.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  function go(to: string) {
    navigate(to);
    setQ("");
    setFocused(false);
    inputRef.current?.blur();
  }

  const fallback = DOC_SEARCH_FALLBACK.filter((slug) => {
    const page = getPage(slug);
    return page && docs.canReadSection(page.sectionKey);
  });

  return (
    <div className="relative w-full max-w-[560px]">
      <div
        className={cn(
          "flex h-11 items-center gap-2 rounded-md border bg-background px-2.5 transition-colors md:h-[38px]",
          focused ? "border-foreground" : "border-input",
        )}
      >
        <Search className="h-4 w-4 shrink-0 text-gray-600" aria-hidden />
        <input
          ref={inputRef}
          type="text"
          value={q}
          aria-label="Search the docs"
          role="combobox"
          aria-expanded={open}
          aria-controls="docs-search-results"
          autoComplete="off"
          onChange={(e) => {
            setQ(e.target.value);
            setSel(0);
          }}
          onFocus={() => setFocused(true)}
          onBlur={() => setTimeout(() => setFocused(false), 150)}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown") {
              e.preventDefault();
              setSel((s) => Math.min(s + 1, Math.max(0, results.length - 1)));
            }
            if (e.key === "ArrowUp") {
              e.preventDefault();
              setSel((s) => Math.max(0, s - 1));
            }
            if (e.key === "Enter" && results[sel]) go(`/docs/${results[sel].slug}`);
            if (e.key === "Escape") {
              setQ("");
              inputRef.current?.blur();
            }
          }}
          placeholder={"Search the docs…"}
          className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-gray-600 focus-visible:ring-0 focus-visible:ring-offset-0"
        />
        {q ? (
          <button
            type="button"
            className="-mr-1 flex h-11 w-11 items-center justify-center text-gray-600 hover:text-foreground md:h-7 md:w-7"
            aria-label="Clear search"
            title="Clear search"
            onClick={() => setQ("")}
          >
            <X className="h-3.5 w-3.5" />
          </button>
        ) : (
          <kbd className="hidden rounded-[3px] border border-border px-1.5 font-mono text-[10px] text-gray-600 md:inline">/</kbd>
        )}
      </div>
      {open && (
        <div
          id="docs-search-results"
          className="absolute z-50 mt-1.5 max-h-[70vh] w-full overflow-auto rounded-lg border border-border bg-popover shadow-md"
        >
          {results.length === 0 && inside.length === 0 ? (
            <div className="px-3 py-3 text-[13px] text-gray-600">
              <p>No matches. Try one of these:</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {fallback.map((slug) => (
                  <button
                    key={slug}
                    type="button"
                    className="inline-flex min-h-11 items-center rounded-full border border-border px-3 text-foreground hover:bg-accent md:min-h-8"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => go(`/docs/${slug}`)}
                  >
                    {getPage(slug)?.title}
                  </button>
                ))}
              </div>
              {fallback.length === 0 && (
                <Link to="/docs" className="inline-flex min-h-11 items-center text-foreground underline" onClick={() => setFocused(false)}>
                  Browse the overview
                </Link>
              )}
            </div>
          ) : (
            <>
              <ul role="listbox" className="py-1">
                {results.map((r, i) => (
                  <li key={r.slug} role="option" aria-selected={i === sel}>
                    <button
                      type="button"
                      className={cn("block min-h-11 w-full px-3 py-2 text-left md:min-h-10", i === sel ? "bg-accent" : "hover:bg-accent")}
                      onMouseEnter={() => setSel(i)}
                      onMouseDown={(e) => {
                        e.preventDefault();
                        go(`/docs/${r.slug}`);
                      }}
                    >
                      <div className="flex items-baseline justify-between gap-3">
                        <span className="min-w-0 text-[14px] font-medium text-foreground">{r.title}</span>
                        <span className="text-[11px] text-gray-600">{r.status === "planned" ? "not written yet" : r.group}</span>
                      </div>
                      {r.summary && <div className="mt-0.5 text-[12.5px] leading-snug text-gray-600">{r.summary}</div>}
                    </button>
                  </li>
                ))}
              </ul>
              {inside.length > 0 && (
                <div className="border-t border-border py-1">
                  <div className="docs-kicker px-3 pb-1 pt-2">Inside pages</div>
                  <ul>
                    {inside.map((h) => (
                      <li key={`${h.page.slug}#${h.id}`}>
                        <button
                          type="button"
                          className="flex min-h-11 w-full items-baseline justify-between gap-3 px-3 py-2 text-left hover:bg-accent md:min-h-10"
                          onMouseDown={(e) => {
                            e.preventDefault();
                            go(`/docs/${h.page.slug}#${h.id}`);
                          }}
                        >
                          <span className="min-w-0 text-[13px] text-foreground">
                            {h.page.title} {"›"} {h.title}
                          </span>
                          <span className="truncate font-mono text-[11px] text-gray-600">#{h.id}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              <div className="hidden border-t border-border px-3 py-2 text-[11px] text-gray-600 md:block">
                {"↑ ↓ to move · ↵ to open · esc to close"}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function NavTree({ activeSlug, onNavigate }: { activeSlug: string; onNavigate: () => void }) {
  // Sixteen sections and eighty pages do not fit on a screen, so only the
  // section you are reading opens by default. `openGroups` holds the reader's
  // own overrides on top of that, keyed by the section's stable key.
  const { docs } = useCapabilities();
  // Sections this reader may not open are left out entirely — released
  // section by section from /admin/docs (docsVisibility.ts).
  const groups = DOC_GROUPS.filter((g) => docs.canReadSection(g.key));
  const activeSection = getPage(activeSlug)?.section ?? -1;
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({});
  return (
    <nav aria-label="Manual" className="text-[13px]">
      <ul className="space-y-0.5">
        {groups.map((g) => {
          const open = openGroups[g.key] ?? g.section === activeSection;
          return (
            <li key={g.key}>
              <button
                type="button"
                aria-expanded={open}
                onClick={() => setOpenGroups((o) => ({ ...o, [g.key]: !open }))}
                className={cn(
                  "flex min-h-11 w-full items-center gap-2 rounded-md px-1.5 text-left text-foreground hover:bg-accent md:min-h-[34px]",
                  open ? "font-semibold" : "font-medium",
                )}
              >
                <ChevronRight
                  className={cn("h-3.5 w-3.5 shrink-0 text-gray-600 transition-transform duration-200 motion-reduce:transition-none", open && "rotate-90")}
                  aria-hidden
                />
                <span className="min-w-0 flex-1">{g.group}</span>
                <span className="text-[11px] font-normal tabular-nums text-gray-600">{g.pages.length}</span>
              </button>
              {open && (
                <ul className="mb-2 mt-0.5 space-y-px">
                  {g.pages.map((p) => {
                    const active = p.slug === activeSlug;
                    return (
                      <li key={p.slug}>
                        <Link
                          to={`/docs/${p.slug}`}
                          onClick={onNavigate}
                          aria-current={active ? "page" : undefined}
                          title={p.status === "planned" ? "Not written yet" : undefined}
                          className={cn(
                            "ml-5 flex min-h-11 items-center gap-2 rounded-r-md border-l-2 py-1 pl-2.5 pr-2 transition-colors md:min-h-[30px]",
                            active
                              ? "border-l-foreground bg-muted/80 font-semibold text-foreground"
                              : "border-transparent text-gray-600 hover:bg-accent hover:text-foreground",
                          )}
                        >
                          <span className={cn("min-w-0 flex-1", p.status === "planned" && "italic")}>{p.title}</span>
                          <span className="font-mono text-[9px] font-normal uppercase tracking-[0.1em] text-gray-600">
                            {KIND_LABEL[p.kind].short}
                          </span>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** "On this page": a track with a fill that grows to the section being read. */
function OnThisPage({ headings, active, onPick }: { headings: Heading[]; active: number; onPick?: () => void }) {
  if (headings.length === 0) return null;
  return (
    <div>
      <div className="mb-2.5 flex items-baseline justify-between text-[12px]">
        <span className="font-semibold text-foreground">On this page</span>
        <span className="tabular-nums text-gray-600">
          {active + 1} of {headings.length}
        </span>
      </div>
      <div className="relative">
        <span aria-hidden className="absolute bottom-0 left-0 top-0 w-0.5 bg-border" />
        <span
          aria-hidden
          className="absolute left-0 top-0 w-0.5 bg-foreground transition-[height] duration-300 ease-[cubic-bezier(.2,0,0,1)] motion-reduce:transition-none"
          style={{ height: `${(100 * (active + 1)) / headings.length}%` }}
        />
        <ul>
          {headings.map((h, i) => (
            <li key={h.id}>
              <a
                href={`#${h.id}`}
                onClick={onPick}
                aria-current={i === active ? "location" : undefined}
                className={cn(
                  "flex min-h-11 items-center py-1 pl-3.5 text-[13px] leading-snug transition-colors md:min-h-8",
                  i <= active ? "text-foreground" : "text-gray-600 hover:text-foreground",
                  i === active && "font-semibold",
                )}
              >
                {h.text}
              </a>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/**
 * The public site's own top bar, above the manual's.
 *
 * /docs is a public address reached from the same nav as /about and /, so it
 * wears the same chrome: a reader who followed "Docs" from the landing page
 * should not feel they have been handed off to a different product, and a
 * reader who arrived from a search result needs a way INTO the product that a
 * bare docs toolbar never gave them.
 *
 * Deliberately NOT sticky, unlike the landing page's. The manual's own toolbar
 * carries the search box and is sticky at top-0, and two stacked sticky bars
 * would cost 7rem of a phone screen on every scroll. This one scrolls away;
 * the one that does the work stays.
 *
 * The right-hand pair depends on who is reading. Signed out, it is the public
 * site's "Log in / Get started". Signed in, offering "Get started" to someone
 * with an account would be a dead end, so it becomes the way back to their
 * workspace. While the session is still resolving it renders neither rather
 * than guessing and swapping under the reader's cursor.
 */
function PublicBar() {
  const { user, loading } = useAuth();
  const { homePath } = useCapabilities();

  return (
    <div className="border-b border-[--hair-rule] bg-background">
      <div className="mx-auto flex h-14 max-w-[1400px] items-center justify-between gap-3 px-4 md:h-16 md:px-6">
        <Link to="/" className="flex items-center" aria-label="SuReSuite home">
          <img
            src="/logo-mark.png"
            alt="SuReSuite — Supply Chain Resilience Suite"
            className="h-[19px] w-auto object-contain md:hidden"
          />
          <img
            src="/logo-lockup.png"
            alt="SuReSuite — Supply Chain Resilience Suite"
            className="hidden h-[58px] object-contain md:block"
          />
        </Link>
        <nav className="flex items-center gap-1 whitespace-nowrap md:gap-2">
          <Button asChild variant="ghost" size="sm" className="hidden md:inline-flex md:h-8">
            <Link to="/about">About</Link>
          </Button>
          <Button asChild variant="secondary" size="sm" className="hidden md:inline-flex md:h-8">
            <Link to="/docs">Docs</Link>
          </Button>
          {!loading &&
            (user ? (
              <Button asChild size="sm" className="h-11 whitespace-nowrap md:h-8">
                <Link to={homePath}>Open app</Link>
              </Button>
            ) : (
              <>
                <Button asChild variant="ghost" size="sm" className="hidden md:inline-flex md:h-8">
                  <Link to="/auth">Log in</Link>
                </Button>
                <Button asChild size="sm" className="h-11 whitespace-nowrap md:h-8">
                  <Link to="/auth">Get started</Link>
                </Button>
              </>
            ))}
        </nav>
      </div>
    </div>
  );
}

/** The slim footer Landing and About both end on. Same reason as PublicBar. */
function PublicFooter() {
  return (
    <footer className="border-t border-[--hair-rule]">
      <div className="pb-safe mx-auto flex min-h-14 max-w-[1400px] flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3.5 text-xs text-muted-foreground md:px-6">
        <span>© {new Date().getFullYear()} SuReSuite</span>
        <div className="flex flex-wrap items-center gap-4">
          <Link to="/about" className="hover:text-foreground">About</Link>
          <Link to="/auth" className="hover:text-foreground">Sign in</Link>
        </div>
      </div>
    </footer>
  );
}

export default function DocsLayout() {
  const location = useLocation();
  // Read from the path, not from useParams: this is the PARENT of the
  // `:slug` route, and a parent match does not carry its child's params.
  // DocPage — the child — reads the param the ordinary way.
  const rawSlug = location.pathname.replace(/^\/docs\/?/, "").split("/")[0];
  // `/docs` itself is the front door (DocsHome), not the first article. Kept as
  // a separate flag rather than a slug of its own: the pager, the rail and the
  // nav highlight are all statements about an ARTICLE, and the home page is
  // not one. `slug` keeps its DEFAULT_SLUG fallback for everything that still
  // needs a page in hand.
  const isHome = !rawSlug;
  const slug = rawSlug || DEFAULT_SLUG;
  const page = getPage(slug);
  const contentRef = useRef<HTMLDivElement>(null);
  const { headings, active, pct } = useReading(contentRef, location.pathname);
  const { docs } = useCapabilities();
  const { user } = useAuth();
  const reader = useMemo(() => ({ userId: user?.id ?? null }), [user?.id]);
  const { prev, next } = prevNext(slug, docs.canReadSection);

  // Below `lg` the nav and "On this page" are sheets, closed until asked for:
  // an open tree pushes the page itself below the fold and the reader lands on
  // a table of contents instead of on the thing they followed a link to.
  const [navOpen, setNavOpen] = useState(false);
  const [tocOpen, setTocOpen] = useState(false);
  const [fontStep, setFontStep] = useState(1);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(FONT_KEY) ?? localStorage.getItem(OLD_FONT_KEY);
      const saved = Number(raw);
      if (raw !== null && !Number.isNaN(saved) && saved >= 0 && saved < FONT_STEPS.length) setFontStep(saved);
    } catch { /* Storage blocked: the default size is fine. */ }
  }, []);
  function changeFont(n: number) {
    setFontStep(n);
    try { localStorage.setItem(FONT_KEY, String(n)); } catch { /* Not persisted; still applied. */ }
  }

  useEffect(() => {
    setNavOpen(false);
    setTocOpen(false);
  }, [location.pathname]);

  // Honor deep links such as the home card's #engineer after the body renders.
  useEffect(() => {
    if (location.hash) {
      let id = location.hash.slice(1);
      try { id = decodeURIComponent(id); } catch { /* Keep a malformed fragment harmless. */ }
      const target = document.getElementById(id);
      if (target && contentRef.current?.contains(target)) target.scrollIntoView({ block: "start" });
      return;
    }
    contentRef.current?.scrollTo?.({ top: 0 });
    window.scrollTo({ top: 0 });
  }, [location.pathname, location.hash, headings]);

  // Empty on the front door. `page` is DEFAULT_SLUG's there, and its related
  // list is a statement about THAT article.
  const related = (isHome ? [] : (page?.related ?? []))
    .map((s) => getPage(s))
    .filter((p): p is NonNullable<typeof p> => Boolean(p) && docs.canReadSection(p.sectionKey));

  const openToc = useCallback(() => setTocOpen(true), []);
  const chrome = useMemo(
    () => ({
      tocButton:
        headings.length > 1 ? (
          <button
            type="button"
            onClick={openToc}
            className="flex min-h-12 w-full items-center gap-2.5 rounded-lg border border-border px-4 text-left text-[14px] text-foreground lg:hidden"
          >
            <ListTree className="h-4 w-4 text-gray-600" aria-hidden />
            <span className="flex-1">On this page {"·"} {headings.length} sections</span>
            <ChevronRight className="h-4 w-4 text-gray-600" aria-hidden />
          </button>
        ) : undefined,
    }),
    [headings.length, openToc],
  );

  return (
    <div className="flex min-h-[calc(100dvh-2.5rem)] flex-col bg-background text-foreground">
      <PublicBar />

      {/* The docs toolbar. The one bar that stays: search lives here. */}
      <header className="sticky top-0 z-30 border-b border-border bg-header-background/95 backdrop-blur">
        <div className="mx-auto flex h-14 max-w-[1400px] items-center gap-2 px-3 md:h-12 md:gap-3 md:px-4">
          <Button
            variant="ghost"
            size="icon"
            className="h-11 w-11 shrink-0 lg:hidden"
            aria-label="Open the manual's contents"
            title="Contents"
            onClick={() => setNavOpen(true)}
          >
            <PanelLeftOpen className="h-4 w-4" />
          </Button>
          <Link
            to="/docs"
            className="flex min-h-11 shrink-0 items-center gap-2 rounded-md px-1.5 text-[14px] font-semibold md:min-h-8"
            aria-label="Docs home"
          >
            <BookOpen className="h-4 w-4" aria-hidden />
            <span className="hidden sm:inline">Docs</span>
          </Link>
          <div className="flex min-w-0 flex-1 justify-center">
            <DocsSearch />
          </div>
          <FontSizeControl step={fontStep} setStep={changeFont} />
        </div>
        {!isHome && (
          <div
            aria-hidden
            className="docs-progress absolute bottom-[-1px] left-0 h-0.5 bg-[var(--brand-red)] transition-[width] duration-[120ms] ease-linear"
            style={{ width: `${pct}%` }}
          />
        )}
      </header>

      <div
        className={cn(
          "mx-auto grid w-full max-w-[1400px] flex-1 grid-cols-1",
          isHome ? "lg:grid-cols-[256px_minmax(0,1fr)]" : "lg:grid-cols-[256px_minmax(0,1fr)_240px]",
        )}
      >
        {/* Left nav — a pane from `lg`, a sheet below it. */}
        <aside className="hidden border-r border-border lg:block">
          <div className="sticky top-12 max-h-[calc(100vh-3rem)] overflow-auto px-3 pb-8 pt-[18px]">
            <NavTree activeSlug={isHome ? "" : slug} onNavigate={() => setNavOpen(false)} />
          </div>
        </aside>
        <Sheet open={navOpen} onOpenChange={setNavOpen}>
          <SheetContent side="left" className="w-[min(320px,88vw)] overflow-auto px-3 pb-safe pt-12">
            <SheetTitle className="sr-only">Contents</SheetTitle>
            <NavTree activeSlug={isHome ? "" : slug} onNavigate={() => setNavOpen(false)} />
          </SheetContent>
        </Sheet>

        {/* The article */}
        <main className="min-w-0 px-[15px] pb-8 pt-5 md:px-8 md:pb-10 md:pt-7 lg:px-12 lg:pb-12 lg:pt-[30px]">
          <div ref={contentRef} style={{ zoom: FONT_STEPS[fontStep] }} className="m-cq">
            <DocsReaderContext.Provider value={reader}>
              <DocsChromeContext.Provider value={chrome}>
                <Outlet />
              </DocsChromeContext.Provider>
            </DocsReaderContext.Provider>
          </div>

          {/* Prev / next pager. The last band on a page with no tab bar under
              it, so it carries the device inset itself (v2 §5.2). Absent on the
              front door: "previous" from a table of contents means nothing. */}
          {!isHome && (prev || next) && (
            <nav
              aria-label="Previous and next page"
              className={cn("pb-safe mt-12 grid grid-cols-1 gap-3 border-t border-border-strong pt-8 md:grid-cols-[repeat(2,minmax(0,1fr))]", KIND_MAX_WIDTH[page?.kind ?? "guide"])}
            >
              {prev ? (
                <Link to={`/docs/${prev.slug}`} className="group rounded-lg border border-border px-[18px] py-4 transition-colors hover:bg-accent">
                  <div className="flex items-center gap-1 text-[12px] text-gray-600">
                    <ArrowLeft className="h-3.5 w-3.5" aria-hidden /> Previous
                  </div>
                  <div className="mt-1 text-[16px] font-semibold text-foreground">{prev.title}</div>
                  {prev.summary && <div className="mt-1 line-clamp-2 text-[14px] leading-snug text-gray-600">{prev.summary}</div>}
                </Link>
              ) : <span className="hidden md:block" />}
              {next ? (
                <Link to={`/docs/${next.slug}`} className="group rounded-lg border border-border px-[18px] py-4 text-right transition-colors hover:bg-accent">
                  <div className="flex items-center justify-end gap-1 text-[12px] text-gray-600">
                    Next <ArrowRight className="h-3.5 w-3.5" aria-hidden />
                  </div>
                  <div className="mt-1 text-[16px] font-semibold text-foreground">{next.title}</div>
                  {next.summary && <div className="mt-1 line-clamp-2 text-[14px] leading-snug text-gray-600">{next.summary}</div>}
                </Link>
              ) : <span />}
            </nav>
          )}
        </main>

        {/* Right rail — "On this page" and "Related", from `lg`. */}
        {!isHome && (
          <aside className="hidden lg:block">
            <div className="sticky top-12 max-h-[calc(100vh-3rem)] space-y-8 overflow-auto px-5 py-[30px]">
              <OnThisPage headings={headings} active={active} />
              {related.length > 0 && (
                <div>
                  <div className="mb-2.5 text-[12px] font-semibold text-foreground">Related</div>
                  <ul className="space-y-3">
                    {related.map((r) => (
                      <li key={r.slug}>
                        <Link to={`/docs/${r.slug}`} className="group block">
                          <div className="text-[13px] font-medium text-foreground group-hover:underline">{r.title}</div>
                          {r.summary && <div className="mt-0.5 text-[12px] leading-snug text-gray-600">{r.summary}</div>}
                        </Link>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </aside>
        )}
        <Sheet open={tocOpen} onOpenChange={setTocOpen}>
          <SheetContent side="bottom" className="max-h-[76%] overflow-auto rounded-t-[12px] px-0 pb-safe pt-3">
            <div aria-hidden className="mx-auto mb-3 h-1 w-9 rounded-full bg-border" />
            <SheetTitle className="px-5 pb-2 text-[14px] font-semibold">On this page</SheetTitle>
            <ul>
              {headings.map((h, i) => (
                <li key={h.id}>
                  <a
                    href={`#${h.id}`}
                    onClick={() => setTocOpen(false)}
                    aria-current={i === active ? "location" : undefined}
                    className={cn("flex min-h-[52px] items-center gap-3.5 border-t border-border px-5", i === active && "bg-muted")}
                  >
                    <span className="font-mono text-[11px] font-semibold tabular-nums text-[var(--brand-red)]">
                      {String(i + 1).padStart(2, "0")}
                    </span>
                    <span className="text-[16px] text-foreground">{h.text}</span>
                  </a>
                </li>
              ))}
            </ul>
          </SheetContent>
        </Sheet>
      </div>

      <PublicFooter />
    </div>
  );
}

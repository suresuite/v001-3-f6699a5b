// The route element behind /docs/:slug.
//
// Four cases, and all four are deliberate:
//   · a live page    → its body
//   · a planned page → a stub naming the work package that owes it
//   · an unknown slug → a "no such page" panel that stays inside the manual
//   · a page in a section not released to this reader → says so, and how to
//     get it (sign in, or ask an administrator) — docsVisibility.ts
//
// The stub is the interesting one. A site map that hid its unwritten pages
// would be a smaller, tidier manual that quietly misrepresents itself — the
// reader cannot tell "this product has no audit log" from "that page is not
// written yet". Naming the owing package makes the absence a fact rather than
// a silence (§5.3 T3).

import type { ReactNode } from "react";
import { Link, useLocation, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { useCapabilities } from "@/hooks/useCapabilities";
import { PageTitle, P, Callout, DocLink, Section } from "@/components/docs/prose";
import { ALL_PAGES, DEFAULT_SLUG, getGroup, getPage } from "@/components/docs/registry";
import { DOC_BODIES } from "@/components/docs/bodies";
import { DocPageContext } from "@/components/docs/docPageContext";
import { KIND_MAX_WIDTH } from "@/components/docs/docKinds";
import { DOCS_INDEX } from "@/components/docs/generated/docsIndex.generated";
import { UploadCard } from "@/components/docs/UploadCard";
import { cn } from "@/lib/utils";

/**
 * The article column every page renders in. `data-kind` selects the template's
 * spacing and numbering in index.css; the width is the kind's reading measure.
 */
function Article({ kind, children }: { kind?: keyof typeof KIND_MAX_WIDTH; children: ReactNode }) {
  return (
    <article className={cn("docs-article", KIND_MAX_WIDTH[kind ?? "guide"])} data-kind={kind}>
      {children}
    </article>
  );
}

function Stub({ slug }: { slug: string }) {
  const page = getPage(slug);
  if (!page) return null;
  const group = getGroup(page.section);
  const siblingsLive = (group?.pages ?? []).filter((p) => p.status === "live");

  return (
    <>
      <PageTitle lead={page.summary}>{page.title}</PageTitle>

      <Callout tone="note" title="Not written yet">
        <p>
          This page is planned and not yet written. It is listed in the navigation rather than left
          out so that you can tell the difference between a feature this product does not have and a
          page this manual has not written.
        </p>
        <p>
          Missing: the{" "}
          {page.kind === "guide" ? "steps" : page.kind === "reference" ? "reference entries" : "explanation"}{" "}
          the summary above promises. The pages below cover what is documented so far.
        </p>
      </Callout>

      {group && (
        <Section id="in-this-section" title="In this section">
          <P>
            <strong className="text-foreground">{group.group}</strong> — {group.blurb}
          </P>
          {siblingsLive.length > 0 && (
            <P>
              Written so far in this section:{" "}
              {siblingsLive.map((s, i) => (
                <span key={s.slug}>
                  {i > 0 && ", "}
                  <DocLink to={s.slug}>{s.title}</DocLink>
                </span>
              ))}
              .
            </P>
          )}
        </Section>
      )}

      <P>
        In the meantime, <DocLink to="data-model">The data model at a glance</DocLink> lists every
        table in the system, and <DocLink to="known-limits">Known limits</DocLink> records what the
        product does not do.
      </P>
    </>
  );
}

/**
 * A page in a section this reader may not open. Said plainly rather than
 * answered with /forbidden or a 404: the page exists, the section has not been
 * released to them, and the two things they can do about it are named.
 */
function NotReleased({ slug }: { slug: string }) {
  const page = getPage(slug);
  const { user } = useAuth();
  const location = useLocation();
  if (!page) return null;
  return (
    <>
      <PageTitle lead={`Part of ${page.group}.`}>{page.title}</PageTitle>
      <Callout tone="note" title="Not available to you">
        <p>
          {user
            ? "This section of the manual has not been released to your account."
            : "This section of the manual is open to signed-in users only."}{" "}
          The manual is released section by section.{" "}
          {user
            ? "If you need it, ask your administrator for access."
            : "Sign in to see whether your account can read it."}
        </p>
        {!user && (
          <Button asChild size="sm" className="mt-1 h-11 md:h-9">
            <Link to="/auth" state={{ from: location }}>Sign in</Link>
          </Button>
        )}
      </Callout>
    </>
  );
}

function Unknown({ slug }: { slug: string }) {
  return (
    <>
      <PageTitle lead="There is no page at this address.">Page not found</PageTitle>
      <P>
        The manual has no page with the address{" "}
        <code className="docs-code">{slug}</code>
        . It may have been renamed, or the link may be from an older version of the site.
      </P>
      <P>
        Use the navigation or search to find the current guide. Start at{" "}
        <DocLink to={DEFAULT_SLUG}>{getPage(DEFAULT_SLUG)?.title}</DocLink>, or use the search box
        above, which covers all {ALL_PAGES.length} pages.
      </P>
    </>
  );
}

export default function DocPage() {
  const params = useParams();
  const slug = params.slug ?? DEFAULT_SLUG;
  const page = getPage(slug);
  const { docs } = useCapabilities();

  const gate = (() => {
    if (!page) return <Unknown slug={slug} />;
    if (!docs.canReadSection(page.sectionKey)) return <NotReleased slug={slug} />;
    return null;
  })();
  if (gate || !page) return <Article>{gate}</Article>;

  const Body = DOC_BODIES[slug];
  const indexed = DOCS_INDEX[slug];
  const meta = {
    page,
    minutes: page.minutes ?? indexed?.minutes ?? null,
    sections: indexed?.sections ?? [],
    // An input table's reference opens with how to upload it (§6.3 section 3).
    summaryCard: page.section === 3 && page.table ? <UploadCard table={page.table} /> : undefined,
  };
  const live = page.status === "live" && Body;

  return (
    <DocPageContext.Provider value={live ? meta : { ...meta, minutes: null, summaryCard: undefined }}>
      <Article kind={page.kind}>{live ? <Body /> : <Stub slug={slug} />}</Article>
    </DocPageContext.Provider>
  );
}

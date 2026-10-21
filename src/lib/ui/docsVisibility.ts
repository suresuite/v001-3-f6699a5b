/**
 * Who may read which part of the manual (PLAN.md §6.5).
 *
 * The manual is released SECTION BY SECTION. A super admin sets each section's
 * audience from /admin/docs, and the answer lives in the database
 * (`docs_section_releases`, `20261001000002`) rather than in a constant here:
 *
 *   public        anyone, signed in or not
 *   internal      any signed-in account
 *   confidential  super admins, and accounts granted `docs_confidential`
 *
 * Every account that can sign in is an approved user — there is no
 * self-sign-up — so "approved" is not a level of its own. Confidential is a
 * GRANT, the `docs_confidential` capability, which the admin screens already
 * edit per role, per organization and per user.
 *
 * FAIL CLOSED. A section with no row, a registry section the database has never
 * heard of, and every section while the releases cannot be read, are all
 * `confidential` — which, with nobody else holding the grant, is exactly the
 * super-admin-only manual the old `DOCS_SUPER_ADMIN_ONLY` flag produced. The
 * database applies the same default (`docs_section_audience`).
 *
 * THE RULE IS APPLIED IN ONE PLACE. `canAccessPage` in useCapabilities answers
 * every docs path through `canReadDocsPath` below, so the route gate, the
 * sidebar, the phone drawer and the manual's own navigation cannot disagree
 * about who sees what (`docsAccess.test.ts`).
 *
 * WHAT IT PROTECTS (T3). Page bodies are compiled into the app bundle, so an
 * audience decides what a reader is SHOWN, not what a determined person can
 * download. The Q&A answers are the exception: they are filtered in the
 * database by `docs_list_faq`.
 */
import { DOC_GROUPS, getPage } from "@/components/docs/registry";
import { canReadSection, sectionAudience, type DocsAudience, type DocsReleases } from "./docsAudience";

// The rules that need no registry live in `docsAudience.ts`, so the always-loaded
// capability gate can apply them without pulling the whole manual's registry into
// the entry bundle; they are re-exported here so no reader of this module changes.
export * from "./docsAudience";

/** Whether the reader can open any section at all — the manual's front door. */
export function canReadAnySection(releases: DocsReleases | null, level: DocsAudience): boolean {
  return DOC_GROUPS.some((g) => canReadSection(releases, g.key, level));
}

/** Whether any section is public — what the public site's Docs links follow. */
export function hasPublicSection(releases: DocsReleases | null): boolean {
  return DOC_GROUPS.some((g) => sectionAudience(releases, g.key) === "public");
}

/**
 * Whether a reader may open a docs path.
 *
 * `/docs/<slug>` of a known page follows that page's section. Everything else
 * under the manual — the index, an unknown slug (which DocPage answers with its
 * own "no such page"), and the legacy `/help` redirects — follows the front
 * door: can this reader open any section at all.
 */
export function canReadDocsPath(pathname: string, releases: DocsReleases | null, level: DocsAudience): boolean {
  const m = /^\/docs\/([^/]+)\/?$/.exec(pathname);
  const page = m ? getPage(m[1]) : undefined;
  if (page) return canReadSection(releases, page.sectionKey, level);
  return canReadAnySection(releases, level);
}

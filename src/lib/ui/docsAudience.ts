/**
 * The manual's audience rules that need no registry (PLAN.md §6.5) — split out of
 * `docsVisibility.ts`, which re-exports all of it.
 *
 * WHY A SEPARATE MODULE. `useCapabilities` is in every page's first load, and it
 * read these through `docsVisibility.ts`, whose registry import put the whole
 * manual's page list (titles, summaries, keywords — about 37 kB of source) in the
 * entry chunk: the bundle audit's initial graph grew from 156.6 to 171.0 kB gzip.
 * The registry-dependent half (`canReadDocsPath`, `canReadAnySection`,
 * `hasPublicSection`) is now loaded with the section releases, which the docs
 * gate already waits for (`docs.loading`), so nothing reads it before it exists.
 */

export type DocsAudience = "public" | "internal" | "confidential";

export const DOCS_AUDIENCES: { value: DocsAudience; label: string; description: string }[] = [
  { value: "public", label: "Public", description: "Anyone can read it, signed in or not." },
  { value: "internal", label: "Internal", description: "Any signed-in user can read it." },
  {
    value: "confidential",
    label: "Confidential",
    description: "Super admins, and users granted Confidential Documentation access.",
  },
];

/** What a section is when nothing says otherwise. */
export const DEFAULT_DOCS_AUDIENCE: DocsAudience = "confidential";

/** section key → audience, as read from `docs_section_releases`. */
export type DocsReleases = Record<string, DocsAudience>;

const RANK: Record<DocsAudience, number> = { public: 0, internal: 1, confidential: 2 };

export function isDocsAudience(value: unknown): value is DocsAudience {
  return value === "public" || value === "internal" || value === "confidential";
}

/** The highest audience a reader may see. */
export function docsReaderLevel(reader: {
  signedIn: boolean;
  isSuperAdmin: boolean;
  hasConfidentialGrant: boolean;
}): DocsAudience {
  if (!reader.signedIn) return "public";
  if (reader.isSuperAdmin || reader.hasConfidentialGrant) return "confidential";
  return "internal";
}

/** A section's audience; unknown or unreadable means confidential. */
export function sectionAudience(releases: DocsReleases | null, sectionKey: string): DocsAudience {
  const a = releases?.[sectionKey];
  return isDocsAudience(a) ? a : DEFAULT_DOCS_AUDIENCE;
}

export function canReadAudience(audience: DocsAudience, level: DocsAudience): boolean {
  return RANK[audience] <= RANK[level];
}

export function canReadSection(releases: DocsReleases | null, sectionKey: string, level: DocsAudience): boolean {
  return canReadAudience(sectionAudience(releases, sectionKey), level);
}

/** True for `/docs`, `/docs/<slug>`, and the legacy `/help` paths that redirect there. */
export function isDocsPath(pathname: string): boolean {
  return /^\/(docs|help)(\/|$)/.test(pathname);
}

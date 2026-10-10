// What the page header needs to know about the page it heads.
//
// A body renders its own `<PageTitle>`, because the h1 and its lead are the
// page's own words. Everything AROUND them — the breadcrumb, the kind pill,
// the reading time, the audience, the troubleshooting jump list, a reference
// page's upload card — is a fact about the page held elsewhere: the registry,
// the generated index, the contract. `DocPage` resolves those once and hands
// them down here, so a body never restates them and `PageTitle` never imports
// the bodies it sits inside.
//
// Absent (null) when a body is rendered on its own, as the body tests do. The
// header then renders the h1 and lead and nothing else — which is also what
// keeps the reading-time count from counting its own label.

import { createContext, useContext, type ReactNode } from "react";
import type { ALL_PAGES } from "@/components/docs/registry";

export type DocPageMeta = {
  page: (typeof ALL_PAGES)[number];
  /** Rounded reading time; null for a page the index does not cover (a stub). */
  minutes: number | null;
  /** The page's `Section` headings, in order — from the generated index. */
  sections: { id: string; title: string }[];
  /** Rendered between the header and the body: a reference page's upload card. */
  summaryCard?: ReactNode;
};

export const DocPageContext = createContext<DocPageMeta | null>(null);

export const useDocPage = () => useContext(DocPageContext);

/**
 * What the docs CHROME lends the page header: the phone's "On this page"
 * button. The layout owns the sheet and the heading list; the header only
 * decides where the button sits (directly under it, per the redesign).
 */
export const DocsChromeContext = createContext<{ tocButton?: ReactNode }>({});

export const useDocsChrome = () => useContext(DocsChromeContext);

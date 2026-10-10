// Networks — Firm-Level Network (guide).
//
// What this lens alone has: firms from the deep-tier tables, tiers counted
// from the seed (`getTierFromDepth`), focus on direct neighbours
// (`firmFocusSet`), stored prominence with its recalculation, the map view
// (node-list coordinates) and the country-risk overlay. The shared controls are
// `networkDocs.tsx`'s.

import {
  DocPageTitle, InShort, Section, P, Callout, Defs, Details, DocTable, Flow, DocLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { AddDisruptionSteps, LensControls } from "@/components/docs/networkDocs";

export default function FirmLevelNetworkGuide() {
  return (
    <>
      <DocPageTitle slug="firm-level-network" />
      <InShort items={[
        <>A graph of <strong>companies</strong>: your plant at the centre, then tier 1, tier 2 and tier 3+ suppliers, from your deep-tier files.</>,
        <>Use it to find shared upstream firms and concentration by country or industry — exposure your product view cannot show.</>,
        <>It is evidence for research, not a simulation input. A missing link may be missing data.</>,
      ]} />

      <Section id="what-you-see" title="A separate company graph">
        <Flow
          caption="Tiers, counted outward from your plant (the seed firm)."
          highlight={0}
          items={[
            { kicker: "seed", title: "Plant", detail: "your firm" },
            { kicker: "depth 1", title: "Tier 1", detail: "supplies you directly" },
            { kicker: "depth 2", title: "Tier 2", detail: "supplies a tier 1" },
            { kicker: "depth 3+", title: "Tier 3", detail: "everything further out" },
          ]}
        />
        <P>Firms come from <DocLink to="deep-tier-nodes">Deep-Tier Nodes</DocLink> and connections from <DocLink to="deep-tier-edges">Deep-Tier Edges</DocLink>: each edge is a recorded <Term>src_uid</Term> → <Term>dst_uid</Term> relationship. A firm marked as the seed is the <strong>Plant</strong>; every other firm's tier is its stored <Term>depth</Term> — 1, 2, and 3 or more all drawn as Tier 3. A firm with no depth is placed with the plant, so check depth coverage before reading the rings.</P>
        <P>Edges are drawn without arrowheads. When direction matters, read the source and destination in the details or the data.</P>
        <DocFigure id="firm-network" />
      </Section>

      <Section id="use-the-view" title="Use the view">
        <LensControls extra={[
          ["Map view · Network view", "Switches the canvas to a map and back. The map plots your project's node list where it has coordinates, with your plant's location; a node without coordinates is not drawn."],
          ["Recalculate prominence", "Runs the prominence analysis on this graph. If this exact graph was already computed it says so and reuses the stored result instead of recalculating."],
          ["Add disruption event", "Opens the disruption dialog for the selected firm — see below."],
        ]} />
        <P>Double-click focuses a firm's <strong>direct connections</strong> only — the firm and its immediate neighbours, not the whole chain behind them. The details panel's <strong>Focus connections</strong> does the same.</P>
      </Section>

      <Section id="the-numbers" title="The numbers beside the graph">
        <Defs items={[
          { term: "Firms · Connections · Tiers", def: "What is on the canvas, and how many of Tier 1–3 have any firm." },
          { term: "Peak prominence", def: <>The highest prominence score in the graph. <DocLink to="network-science-metrics">Network science metrics</DocLink> defines prominence; the chip beside the analytics says whether the numbers come from a stored analysis of this exact graph or an older one.</> },
          { term: "Firm details", def: "Incoming and outgoing connections, revenue, country, industry and prominence for the selected firm." },
        ]} />
        <DocTable
          caption="The analytics panels."
          head={["Panel", "Shows"]}
          rows={[
            ["Prominence statistics", "How prominence is distributed, and how it was calculated"],
            ["Tier composition", "The share of firms in each tier"],
            ["Revenue coverage", "How many firms in each tier have a known revenue — read this before any revenue chart"],
            ["Single-source exposure", "Up to ten firms with exactly one upstream supplier that still supply someone downstream, with tier, country and that country's risk class — a failure upstream of them passes straight through"],
            ["Top firms by revenue · Most connected firms", "Rankings by revenue and by number of connections"],
          ]}
        />
        <Callout tone="note" title="Country risk comes from a table, and can be missing">
          <p>Each firm's risk class is looked up by its country in the platform's country-risk table. If that table returns nothing, the page says so on screen rather than showing every firm as unrated; a firm whose country is not listed reads <Term>Unknown</Term>.</p>
        </Callout>
        <P>Revenue and relative revenue are company attributes, not material quantities. A weight shown where revenue is missing may be a fallback — check revenue coverage before reading it as money or purchasing share.</P>
      </Section>

      <Section id="worked-example" title="Why the tutorial may have no firm graph">
        <P>The control-unit files describe S-BOARD and S-CASE supplying Assembly, and Assembly serving C-ASSEMBLY — operational lanes, not company relationships. They include no deep-tier files, so the firm view is empty after the tutorial. That is not a failure of the product network.</P>
        <DocTable
          caption="To extend the tutorial, a minimal deep-tier pair might look like this (illustrative)."
          head={["File", "Rows"]}
          rows={[
            ["Deep-tier nodes", "ASSEMBLY (seed, depth 0) · S-BOARD (depth 1) · CHIPCO (depth 2)"],
            ["Deep-tier edges", "S-BOARD → ASSEMBLY · CHIPCO → S-BOARD"],
          ]}
        />
        <P>Collect relationships with stable company identifiers and keep the evidence. A company name, a directory entry or a capability is not proof that it supplies a named buyer — keep possible suppliers separate from established ones in your research data.</P>
      </Section>

      <Section id="questions" title="Questions this graph can support">
        <P>Recorded shared upstream dependencies; concentration in a country or industry; firms with many connections; tier-2 firms that several of your tier-1s depend on. A common upstream firm suggests correlated exposure — within the network you observed, and only as good as the evidence behind it.</P>
        <P>Low connectivity can be a sparse chain, or incomplete collection, unresolved company identities, edges whose endpoint has no node, or a focus you forgot to clear. “No shared supplier found” is not “the suppliers are independent”: report coverage with any conclusion.</P>
      </Section>

      <Section id="add-disruption" title="Turn a firm into a scenario">
        <P>The engine disrupts your project's suppliers and its plant. A deep-tier firm that is not one of your suppliers cannot be targeted directly; the dialog offers the suppliers connected to it instead.</P>
        <AddDisruptionSteps />
      </Section>

      <Section id="upload" title="Review deep-tier files before importing">
        <P>Deep-tier files load through a bulk path, not the staged review used for the BOM and logistics: there is no comparison screen and no promotion step. Keep the previous export, check that every edge's endpoints exist as nodes, and read <DocLink to="deep-tier-nodes">Deep-Tier Nodes</DocLink> and <DocLink to="deep-tier-edges">Deep-Tier Edges</DocLink> first.</P>
        <P>Check the tier and direction conventions of your source. Don't use BOM level as a company tier, and don't fill unknown weights with invented transaction values.</P>
      </Section>

      <Section id="simulation" title="What this graph does not simulate">
        <P>The simulation reads operational suppliers, materials, products, the BOM and demand. Deep-tier company edges do not become capacity-constrained upstream stages, and prominence is not an engine input. A central firm here is a research lead, not a measured impact — to measure one, disrupt the supplier that depends on it and compare.</P>
        <Details title="How this works: depth, seed and tier">
          <p>Tier is computed from two stored fields per firm: <Term>is_seed</Term> (the plant) and <Term>depth</Term>. It is not recomputed from the edges on screen, so a firm whose stored depth is out of date will sit in the wrong ring until the deep-tier data is refreshed.</p>
        </Details>
        <P>Next: <DocLink to="network-science-metrics">network measures</DocLink>, or the operational <DocLink to="product-level-network">product graph</DocLink>.</P>
      </Section>
    </>
  );
}

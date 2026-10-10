// Networks — Process-Level Network (guide).
//
// What this lens alone has: BOM-depth columns read from `bom_multi_level`
// (not from the lane `level`, which two writers once disagreed about — §4 D140),
// the Level 1 filter answered by the stored `process_structure` reachability,
// directed focus (`directedFocusIds`), and its own analytics. The shared
// controls are `networkDocs.tsx`'s.

import {
  DocPageTitle, InShort, Section, P, Callout, Defs, Details, DocTable, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { AddDisruptionSteps, LensControls } from "@/components/docs/networkDocs";

export default function ProcessLevelNetworkGuide() {
  return (
    <>
      <DocPageTitle slug="process-level-network" />
      <InShort items={[
        <>This is the BOM opened up: suppliers, materials at each BOM depth, products and customers, in columns.</>,
        <>Depth comes from your multi-level BOM. It counts component steps, not machines, routings or company tiers.</>,
        <>Use it to see what a sub-assembly depends on. The simulation still runs one production stage.</>,
      ]} />

      <Section id="what-you-see" title="What a process node means here">
        <Flow
          caption="The columns, in flow order. Materials are split by how deep in the BOM they sit."
          items={[
            { title: "Suppliers", detail: "one step before what they feed" },
            { title: "Deepest materials", detail: "e.g. chips" },
            { title: "Shallower materials", detail: "e.g. board assembly" },
            { title: "Products", detail: "finished goods" },
            { title: "Customers", detail: "demand" },
          ]}
        />
        <P>Nodes and edges come from the project's multi-tier lanes; each material's <strong>depth</strong> is read from your <DocLink to="bom-multi-level">multi-level BOM</DocLink>. A supplier sits one column before the deepest material it supplies. If the BOM cannot be read, depth shows as unknown and the page says so — the graph is still right about what connects to what.</P>
        <P>It is a view of component relationships, not a routing model: no machines, process steps or labour stations. Each edge is labelled with its weekly flow and drawn wider as the flow grows; a component that goes into several products carries the sum of all of them, in every plant. Position and size say nothing about processing time or capacity.</P>
        <DocFigure id="process-network" />
      </Section>

      <Section id="use-the-view" title="Use the view">
        <LensControls extra={[
          ["Labels (tag icon)", "Hides or shows node IDs and edge flows. On by default."],
          ["Level 1 filter", "Pick one of the nodes the lane data marks as level 1; the canvas keeps only what is upstream or downstream of it. All Nodes, or the clear button, restores the rest."],
          ["Add disruption event", "Opens the disruption dialog for the selected node — see below."],
        ]} />
        <P>Double-click focuses the <strong>process chain</strong>: everything reachable from the node following the edges forward, and everything that reaches it following them back. The details panel's <strong>Focus process chain</strong> does the same.</P>
        <P>The Level 1 filter's reachability is computed and stored by the database, not by your browser. If it is still being computed, the page says to try again in a moment; if the node has none stored, it says it is not a level 1 node of this network.</P>
      </Section>

      <Section id="the-numbers" title="The numbers beside the graph">
        <Defs items={[
          { term: "Nodes · Edges", def: "What is on the canvas." },
          { term: "BOM depth", def: "The deepest level in your multi-level BOM; a dash when no depth could be read." },
          { term: "Products", def: "How many finished products the graph contains." },
          { term: "Component details", def: <>For the selected node: its ID, the lane's raw <Term>level</Term> (shown as stored, not as depth), the data source, incoming, outgoing and total connections, and flow volume.</> },
        ]} />
        <DocTable
          caption="The analytics panels."
          head={["Panel", "Shows", "Use it to"]}
          rows={[
            ["Top nodes by flow volume", "The ten nodes handling the most weighted flow, by depth", "See where volume concentrates"],
            ["Level connectivity summary", "Average connections and flow at each BOM depth", "Spot a thin level — few nodes carrying everything"],
          ]}
        />
        <Callout tone="tip" title="Volume is not criticality">
          <p>A low-flow component can still stop every product that needs it. Read a short bar as “cheap to buffer”, never as “safe to ignore”.</p>
        </Callout>
      </Section>

      <Section id="worked-example" title="The same control unit at two depths">
        <P>The <DocLink to="your-first-project">tutorial</DocLink> uses a single-level BOM — one board and two housings straight into P-CONTROL — so its process view looks almost like the <DocLink to="product-level-network">product view</DocLink>, and <strong>BOM depth</strong> shows a dash because there is no multi-level BOM to read a depth from. That is expected, not a fault.</P>
        <DocTable
          caption="An illustration, not part of the tutorial files: a board assembly that is itself built."
          head={["Component", "Goes into", "Per unit of parent", "Per P-CONTROL", "Depth"]}
          rows={[
            ["Chip", "Board assembly", "2", "2 × 1 = 2", "2"],
            ["Board assembly", "P-CONTROL", "1", "1", "1"],
            ["Housing", "P-CONTROL", "2", "2", "1"],
          ]}
        />
        <P>At 100 products a week, that is 200 chips, 100 board assemblies and 200 housings a week. The process view shows the chain chip → board assembly → P-CONTROL; the product view collapses it to chip → P-CONTROL with a flow of 200.</P>
      </Section>

      <Section id="tiers" title="BOM depth is not company tier">
        <P>BOM depth counts component steps inside a product. Company tier counts supplier relationships away from your firm, in the <DocLink to="firm-level-network">firm view</DocLink>. A tier-one supplier can deliver a part four BOM levels down; a tier-three firm can make a top-level component. Never carry one number across to the other.</P>
      </Section>

      <Section id="focus" title="Follow a dependency without losing context">
        <P>Search for the component, double-click it, read the chain, then <strong>Show all</strong> before judging overall connectivity.</P>
        <P>If a component is isolated: check the higher-level component IDs, the product roots, the consumption rates and which BOM the project is set up for, then filters and whether derived data needs refreshing — in that order. Don't add a speculative edge to make the picture connected.</P>
      </Section>

      <Section id="disruption" title="From graph inspection to a scenario">
        <AddDisruptionSteps />
        <Callout tone="warning" title="Displayed depth is not simulated depth">
          <p>The worker flattens a multi-level BOM into root-to-leaf requirements for the single-stage engine. Intermediate stock, work in progress, lead time and capacity are not simulated, so a sub-assembly bottleneck seen here cannot be tested as one — target the supplier behind it instead.</p>
        </Callout>
        <Details title="How this works: where the columns come from">
          <p>Node roles come from the lanes (who supplies, who buys); a material's column comes from its depth in <Term>bom_multi_level</Term>; a supplier sits one step beyond the deepest material it feeds. The same placement rule draws the <AppLink to="/network/interactive-space">interactive network space</AppLink>, so the two cannot disagree about where a node belongs.</p>
          <p>A depth the BOM does not state is shown as unknown, never as 0.</p>
        </Details>
        <P>Next: <DocLink to="firm-level-network">company relationships</DocLink> and <DocLink to="disruptions">disruption configuration</DocLink>.</P>
      </Section>
    </>
  );
}

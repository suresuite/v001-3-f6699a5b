// Networks — Product-Level Network (guide).
//
// The page's own facts: four echelon columns, the right rail's numbers and
// what each is computed from (`utils/networkMetrics.ts`), the analytics panels,
// the focus rule (`productFocusSet`) and the phone composition. The controls
// it shares with the other two lenses are `networkDocs.tsx`'s, written once.

import {
  DocPageTitle, InShort, Section, P, Callout, Defs, DocTable, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { AddDisruptionSteps, LensControls } from "@/components/docs/networkDocs";

export default function ProductLevelNetworkGuide() {
  return (
    <>
      <DocPageTitle slug="product-level-network" />
      <InShort items={[
        <>Four columns, left to right: suppliers, purchased materials, finished products, customers. Edges are your lanes and BOM lines.</>,
        <>Each edge carries a weekly flow computed from demand — the number, and its width. It is not a measured shipment.</>,
        <>Use it to find single-source materials and shared dependencies, then turn a node into a disruption scenario.</>,
      ]} />

      <Section id="what-you-see" title="Read the four columns">
        <Flow
          caption="The product lens, left to right. Colours mark the column, not a risk rating."
          items={[
            { kicker: "A", title: "Suppliers", detail: "from inbound lanes" },
            { kicker: "B", title: "Materials", detail: "purchased items" },
            { kicker: "C", title: "Products", detail: "finished goods" },
            { kicker: "D", title: "Customers", detail: "from outbound lanes" },
          ]}
        />
        <P>The view is built from your project's computed supply-chain lanes — see <DocLink to="supply-chain-data">Supply chain data</DocLink>. An edge exists because a lane or a BOM line says so; a supplier, material or customer row on its own draws nothing.</P>
        <P>Every edge is labelled with its <strong>weekly flow</strong> and drawn wider as the flow grows. The flow is computed from demand, the same number the <DocLink to="process-level-network">process view</DocLink> shows for the same lane: a supplier's share of its material's demand, a material's demand pushed down the BOM to each product, and a product's outbound volume — each summed over every plant.</P>
        <DocFigure id="product-network" />
      </Section>

      <Section id="use-the-view" title="Use the view">
        <LensControls extra={[
          ["Labels (tag icon)", "Hides or shows node IDs and edge flows. On by default."],
          ["Add disruption event", "Opens the disruption dialog for the selected node — see below."],
        ]} />
        <P>Double-clicking focuses the <strong>supply path</strong>: from a supplier, the materials it sends, the products they go into and the customers who buy them; from a customer, the same chain run backwards. The details panel's <strong>Focus supply path</strong> button does the same.</P>
        <Callout tone="note" title="On a phone">
          <p>The graph, the map view and the supplier charts are desktop surfaces. On a phone the page shows the same findings as numbers and lists; open it on a larger screen to explore the graph.</p>
        </Callout>
      </Section>

      <Section id="the-numbers" title="The numbers beside the graph">
        <Defs items={[
          { term: "Nodes · Edges · Echelons", def: "What is on the canvas, and how many of the four columns have anything in them." },
          { term: "Single-source %", def: <>Of the materials with at least one inbound lane, the share that has exactly <strong>one</strong> supplier. It counts suppliers, not volume: a material with a second supplier carrying 1% of the volume is not single-source here.</> },
          { term: "Node details", def: <>For the selected node: incoming and outgoing connections, and incoming and outgoing weekly flow.</> },
        ]} />
        <P>Open <strong>Analytics</strong> for the charts underneath:</P>
        <DocTable
          caption="The analytics panels, and what each one is computed from."
          head={["Panel", "Shows", "Reads it as"]}
          rows={[
            ["Supplier volume", "Inbound volume per supplier, with material diversity and material concentration", "Concentration: the share of materials where one supplier carries more than 70% of the volume"],
            ["Supplier–material spread", "How many materials each supplier sends, with supplier diversity and single-source %", "A supplier sending many materials is a wide single point of failure"],
            ["Network metrics", "Centrality of every material in this lens, with when it was last calculated", <>Where each number came from — stored analysis or a fresh calculation — is stated beside the table. <DocLink to="network-science-metrics">Network science metrics</DocLink> defines each one.</>],
          ]}
        />
        <P>The <strong>Nexus Node Prediction</strong> card on the right scores nodes by how much demand is at risk if they fail. It is a static, first-order score, not a simulated loss.</P>
      </Section>

      <Section id="worked-example" title="Find P-CONTROL in the tutorial">
        <P>Load the <DocLink to="your-first-project">control-unit example</DocLink> and open <AppLink to="/network/product-level">the product view</AppLink>. Search for <Term>P-CONTROL</Term> and double-click it: the canvas keeps S-BOARD and S-CASE, M-BOARD and M-CASE, P-CONTROL and C-ASSEMBLY.</P>
        <DocTable
          caption="The tutorial's edges, as the product view labels them."
          head={["Edge", "Weekly flow", "Why"]}
          rows={[
            ["S-BOARD → M-BOARD", "100", "the only board supplier carries all 100 boards"],
            ["S-CASE → M-CASE", "200", "the only housing supplier carries all 200 housings"],
            ["M-BOARD → P-CONTROL", "100", "1 board per product × 100 products"],
            ["M-CASE → P-CONTROL", "200", "2 housings per product × 100 products"],
            ["P-CONTROL → C-ASSEMBLY", "100", "the outbound lane's demand"],
          ]}
        />
        <P>Single-source % reads 100%: both materials have one supplier each. Don't add the flows of different materials together — 100 boards and 200 housings are not 300 of anything.</P>
      </Section>

      <Section id="questions" title="What this view can answer">
        <P>Which products share a purchased material; which materials have only one recorded supplier; how much customer demand hangs off a product. Focus a node to see its whole chain, then <strong>Show all</strong> before you conclude that a connection is missing.</P>
        <P>A second supplier is an alternative only if your data and operating assumptions say it can take the volume. Two supplier nodes also don't prove two independent upstream sources — they may buy from the same firm, which is what the <DocLink to="firm-level-network">firm view</DocLink> is for.</P>
      </Section>

      <Section id="add-disruption" title="Turn a node into a scenario">
        <AddDisruptionSteps />
      </Section>

      <Section id="missing" title="When an edge is missing">
        <P>Check the selected project, whether you are focused on another node, the identifier spelling, whether the rows were accepted, and whether derived data needs refreshing. A master row does not create a lane or a BOM line. A disconnected material may be deliberately unused, mistyped, or waiting for its relationships.</P>
        <P>With a multi-level BOM, this view collapses the internal structure into purchased material → finished product. Use the <DocLink to="process-level-network">process view</DocLink> to see the intermediate components.</P>
      </Section>

      <Section id="simulation" title="What reaches simulation">
        <P>The engine reads the accepted BOM, supplier/material lanes and customer/product demand. The layout, node sizes and centralities are not simulation inputs. The engine models one focal production stage, so a multi-level BOM on screen does not create intermediate stock, capacity or processing time.</P>
        <P>Next: <DocLink to="process-level-network">inspect BOM depth</DocLink>, then <DocLink to="how-policies-work">set operating policies</DocLink>, and read the conversion notes after a run to confirm the mapping.</P>
      </Section>
    </>
  );
}

// Getting started — Your first project (journey page, WP 5.2a redesign).
//
// A guided build in numbered sections, each ending on a "You should see"
// checkpoint. Section ids are unchanged — `pageDepth.test.tsx` holds six.
// The numbers (capacities, protocol settings, results) are the ones the old
// page carried and `manualExample.test.ts` checks against the tutorial files;
// none is new.

import {
  DocPageTitle, InShort, Section, P, Callout, Check, Steps, Defs, Details, DocTable, Flow, Stats,
  DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { ExampleDownloads } from "@/components/docs/ExampleDownloads";

export default function Guide() { return <>
<DocPageTitle slug="your-first-project" />
<InShort items={[
  <>A guided build: two suppliers, two materials, one product, one customer.</>,
  <>You'll compare three runs — the baseline, a four-week board disruption, and the same disruption with a stock buffer.</>,
  <>Every step ends in a checkpoint, so you know it worked before you move on.</>,
]} />

<Section id="before-you-start" title="Before you start">
  <Stats items={[["Suppliers", "2"], ["Materials", "2"], ["Products", "1"], ["Customers", "1"], ["Demand", "100 / week"]]} />
  <P>Use a new project for this, so nothing you do touches real work. You need rights to create a project, edit its inputs and policies, and run simulations. If a control is greyed out, check your project rights on your profile or ask the project owner. Opening the manual does not grant access to a project.</P>
  <P>All names and numbers are made up. The model has one production stage; it doesn't simulate individual factory operations or find suppliers for you.</P>
  <ExampleDownloads />
  <DocFigure id="first-comparison" />
</Section>

<Section id="create" title="Create the project">
  <P>Open <AppLink to="/project-manager">Project Manager</AppLink> › <strong>New Project</strong>. Name it <Term>Control-unit tutorial</Term>, set Plant to <Term>Assembly</Term>, and choose <strong>Curated data</strong>, <strong>Make-To-Order</strong> and <strong>Single Level</strong> BOM. Leave deep-tier exploration off, then choose <strong>Create Project</strong>.</P>
  <Check>the new project in your list. Select it before you upload anything.</Check>
</Section>

<Section id="upload" title="Upload and accept seven files">
  <Steps steps={[
    { title: "Upload the four item lists", where: "Upload Data", body: <>Suppliers, Materials, Products, Customers — each on its own dataset tab. These make the IDs easy to check.</> },
    { title: "Upload the three relationship files", where: "Upload Data", body: <>BOM — single level, Inbound Logistics, Outbound Logistics. These are what actually connect the chain.</> },
    { title: "Review and accept each one", where: "Review", body: <>Check new, changed, unchanged and held rows, then choose <strong>Promote N rows</strong>. Uploading alone is not accepting, and held rows are not accepted. <DocLink to="uploading-data">Uploading data</DocLink> covers corrections.</> },
    { title: "Refresh if asked", where: "Project Manager", body: <>Once the three core datasets are in, use <strong>Refresh Data</strong> if Project Manager asks you to finish building derived data.</> },
  ]} />
  <Check>two BOM lines, two inbound lanes and one outbound lane. P-CONTROL needs one M-BOARD and two M-CASE; C-ASSEMBLY wants 100 P-CONTROL a week.</Check>
</Section>

<Section id="inspect" title="Check the relationships">
  <P>Open the <DocLink to="product-level-network">product view</DocLink> and search for <Term>P-CONTROL</Term>. Follow both materials back to their suppliers.</P>
  <P>At 100 products a week the BOM needs 100 boards and 200 housings a week. Supplier capacities are 150 and 300 units a week; product capacity is 150 a week — so there is headroom, for now.</P>
  <DocTable
    caption="Weekly requirement against capacity, before and during the disruption."
    head={["Item", "Needed per week", "Capacity per week", "During weeks 16–19"]}
    rows={[
      ["M-BOARD from S-BOARD", "100", "150", "30 (80% cut)"],
      ["M-CASE from S-CASE", "200", "300", "300"],
      ["P-CONTROL at the plant", "100", "150", "150"],
    ]}
  />
  <Callout tone="tip" title="A link is missing?">
    <p>Check the IDs in the lane or BOM file, whether the rows were accepted, which project is selected, and any graph filters. A gap in the graph doesn't prove a gap in the real chain.</p>
  </Callout>
</Section>

<Section id="policies" title="Save and validate the baseline">
  <Steps steps={[
    { title: "Supplier stage", where: "/policies", body: <>On <AppLink to="/policies">Policies</AppLink>, check S-BOARD supplies M-BOARD and S-CASE supplies M-CASE, each as the single primary source. Set <strong>Planning time unit</strong> to weeks where asked. Use min-max replenishment, 2 weeks of coverage and 0 days of <strong>Safety stock</strong> on both materials. Keep the uploaded opening stock: 200 boards, 400 housings.</> },
    { title: "Plant stage", where: "/policies", body: <>P-CONTROL has finished-goods stock off (make-to-order) and capacity 150 a week.</> },
    { title: "Customer stage", where: "/policies", body: <>C-ASSEMBLY / P-CONTROL has fixed demand of 100 a week, is supplied from the focal plant, and has backordering off. Demand is edited here.</> },
    { title: "Run & Validate", where: "/policies", body: <>Save, then clear blocking findings and read every warning before acknowledging defaults. The tutorial protocol uses a 455-day horizon, 56-day warm-up, seed 42 and 3 replications. Choose <strong>Save Validated Model</strong> when the evidence is acceptable.</> },
  ]} />
  <Check>a saved Validated Model and a finished baseline. Note the settings and version IDs — you'll reuse them.</Check>
  <Details title="Why these settings">
    <p>Three replications are a teaching setting for a fixed-demand example. They are not evidence that three is enough for a business study with uncertain demand.</p>
    <p>A primary-source choice satisfies the app's routing checks; the engine's actual sourcing also depends on its policy and lane data.</p>
  </Details>
</Section>

<Section id="disrupt" title="Add one disruption and run">
  <P>Open <AppLink to="/simulation-lab">Simulation Lab</AppLink>, copy the validated baseline to a new scenario called <Term>Board disruption</Term>, and add one event in <strong>Recovery playbook</strong>:</P>
  <Defs items={[
    { term: "Target", def: <Term>S-BOARD</Term> },
    { term: "Type", def: "Capacity reduction, 80%" },
    { term: "When", def: <>Week 16, for 4 weeks (<Term>start_day</Term> 112, <Term>duration_days</Term> 28)</> },
    { term: "Keep the same", def: "Seed, common random numbers, data, policy version, horizon and warm-up. Leave recovery levers off." },
  ]} />
  <P>Go to <strong>Run</strong>, review the gate, and dispatch. Wait for <strong>done</strong> with the expected replication count, and read the conversion notes before you trust the result. A queued or running result is preliminary; a failed run needs its error resolved before you retry.</P>
</Section>

<Section id="reading-the-first-result" title="Compare the runs">
  <Flow
    caption="The three runs. Change one thing at a time, so each comparison isolates one effect."
    items={[
      { kicker: "Run 1", title: "Baseline", detail: "validated, no disruption" },
      { kicker: "Run 2", title: "Board disruption", detail: "same settings + one event" },
      { kicker: "Run 3", title: "With buffer", detail: "same event + 28-day stock" },
    ]}
  />
  <P>In <strong>Compare</strong>, pick the baseline, then the Board disruption column. Only the disruption should differ. Read fill rate and lost sales together with the weekly trace. If the comparison refuses the pair, read its reason — a seed mismatch, common random numbers off, an engine mismatch, or more than one change.</P>
  <P>To test a response, save a second policy version with 28 days of material safety stock and run the same disruption under it. Extra stock has a cost; don't call better service a net win until you've checked it.</P>
</Section>

<Section id="local-results" title="What you should get">
  <DocTable
    caption="Engine 0.6.1 results for the downloadable protocol, 52 measured weeks after an 8-week warm-up."
    head={["Run", "Fill rate", "Lost-sales value", "Cost of resilience"]}
    rows={[
      ["Baseline", "100%", "0", "0"],
      ["Board disruption", "95.9615%", "12,600", "12,600"],
      ["Same disruption, with buffer", "100%", "0", "2,400"],
    ]}
  />
  <P>At 100 products a week and a selling price of 60, measured demand is worth 312,000. The disruption loses 12,600 of it: 1 − 12,600 / 312,000 ≈ 95.96%. The buffer avoids that loss in this fixed example while adding holding cost.</P>
  <Details title="What has and hasn't been verified">
    <p>The downloadable files pass the repository's CSV parser and contract validator, and the exact protocol runs locally through the worker's frozen-input pipeline. Its output records the engine version, KPIs and conversion notes.</p>
    <p>Database promotion, browser-to-worker dispatch and a hosted app run have not been executed for this tutorial. UI defaults may differ from the protocol, so record what your run actually used.</p>
    <p>All three replications are identical because the inputs are fixed. That is not a statement about real-world certainty.</p>
  </Details>
  <P>Next: <DocLink to="reading-your-results">read the evidence behind the numbers</DocLink>, then <DocLink to="experiments-and-comparison">design a controlled comparison</DocLink>.</P>
</Section>
</>; }

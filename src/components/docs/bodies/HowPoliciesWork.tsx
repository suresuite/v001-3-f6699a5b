// Policies — How policies work (journey page, WP 5.2a redesign).
//
// A concept page that leads with what a policy changes in a planner's words.
// The notation — s, S, T, (R,Q), κ — and the lead-time rounding rule are kept,
// collapsed, after the plain explanation. Section ids are unchanged;
// `pageDepth.test.tsx` holds four of them.

import {
  DocPageTitle, InShort, Section, P, Callout, Steps, Defs, Details, DocTable, Flow, DocLink, AppLink,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

export default function Guide() { return <>
<DocPageTitle slug="how-policies-work" />
<InShort items={[
  <>Your data describes the chain. Policies decide how it behaves. Same data, different policies, different results.</>,
  <>Each field resolves on its own: your override, then the uploaded value, then a stated default. There's no single ladder.</>,
  <>A value only matters if the simulation reads it — check the stage reference for each field.</>,
]} />

<Section id="what-a-policy-is" title="What a policy changes">
  <P>Inputs describe demand, the BOM, lanes and capacities. Policies decide replenishment, sourcing, production and what happens to demand you can't meet. On <AppLink to="/policies">Policies</AppLink>, work through the Supplier, Plant and Customer stages, then <strong>Run &amp; Validate</strong>.</P>
  <DocTable
    caption="The three stages, with fields used in the tutorial."
    head={["Stage", "Decides", "Example fields"]}
    rows={[
      ["Supplier", "Where materials come from and how they are replenished", "Primary source · replenishment type · coverage · safety stock · lead-time override"],
      ["Plant", "What is made and whether finished goods are stocked", "Finished-goods stock (make-to-stock / make-to-order) · capacity"],
      ["Customer", "Demand and how it is served", "Demand · fulfilment source · backordering"],
    ]}
  />
  <P>Each cell shows where its value came from: an unsaved draft, a saved override, a project default, or your upload. Those are different states.</P>
  <DocFigure id="resolution-order" />
</Section>

<Section id="precedence" title="Where a value comes from">
  <Flow
    caption="A master-backed field, such as material cost, resolves left to right. Other fields have their own chains."
    items={[
      { kicker: "1", title: "Saved override", detail: "on the policy row" },
      { kicker: "2", title: "Uploaded value", detail: "item master or lane" },
      { kicker: "3", title: "Derived value", detail: "e.g. from lanes" },
      { kicker: "4", title: "Stated default", detail: "marked as such" },
    ]}
  />
  <P>Look at each field on its own. For a cost read from the item master, a saved override replaces the uploaded value; with neither, a value derived from lanes or an explicit default applies. Demand, lead time and finished-goods fields follow their own chains, listed on the stage references.</P>
  <Defs items={[
    { term: "An example", def: "M-BOARD costs 20 in the tutorial master. An override of 25 changes the simulated valuation and leaves the master at 20. Removing the override restores 20; re-uploading the master doesn't remove it." },
    { term: "Blank isn't zero", def: "A blank can mean no override, derive a value, or use a default. Zero opening stock starts empty; zero safety-stock days asks for no fixed buffer. Check the field's limits before you type 0." },
    { term: "Lead time", def: "The Supplier-stage cell can override a lane without changing the lane. An override wins; otherwise the lane, or a two-week default if the lane has none. The exception is a lane whose lead-time shape is triangular or uniform: the run plans on the mean of its bounds, the cell shows that mean as a derived value, and a lead time typed on the row is not read." },
  ]} />
  <Details title="How this works: lead time and finished-goods targets">
    <p>Lead-time entry uses whole weeks, rounded half to even and clamped to 1–51, matching the engine. Removing the override restores the lane/default chain.</p>
    <p>For make-to-stock products, an explicit base-stock target S is the target; the finished-goods safety buffer is not added again. When S is missing, a target can be derived. There is no new finished-goods safety-buffer control: a value saved by an older policy appears as a legacy notice with Remove. Make-to-order products don't use finished-goods stock controls.</p>
  </Details>
</Section>

<Section id="replenishment" title="Replenishment types, briefly">
  <P>A reorder point or target you type is an absolute level — nothing is added on top. Leave it empty to use the formula and its buffer. MRP takes replenishment from the plan.</P>
  <Details title="Notation: s, S, T and (R,Q)">
    <p>A typed material reorder point s or target S is an absolute level; the engine does not add safety stock to it. Periodic replenishment reads its review period T.</p>
    <p>An (R,Q) row needs a positive lot Q, on the row or inherited from the project; it has no coverage κ control. A parameter stored for a previous type is dropped by the conversion, with a warning.</p>
  </Details>
</Section>

<Section id="worked-response" title="Try it: test a stock buffer">
  <Steps steps={[
    { title: "Start from the tutorial baseline", where: "/policies", body: "Min-max replenishment, 2 weeks of coverage, 0 days of safety stock, explicit opening quantities. At 100 products a week the BOM needs 100 boards and 200 housings a week." },
    { title: "Change one thing", where: "Supplier stage", body: <>Set <strong>Safety stock</strong> to 28 days on the material rows. Don't touch demand, opening stock or the disruption.</> },
    { title: "Save a new version and rerun", where: "Run & Validate", body: "Keep the baseline version, rerun the same supplier disruption, and compare service and holding cost together.", check: "two policy versions you can compare side by side." },
  ]} />
  <P>The 28-day figure is illustrative. A buffer can improve service and still cost more than it saves.</P>
</Section>

<Section id="save" title="Drafts, versions and Validated Models">
  <Defs items={[
    { term: "Draft", def: "An edited cell that isn't saved yet. Save, and check that no unsaved marker remains." },
    { term: "Policy version", def: "A saved set of policies, captured for a run." },
    { term: "Preset", def: "A reusable starting point — not evidence that it suits your chain." },
    { term: "Validated Model", def: "Binds policy and dataset versions to validation evidence and adopted simulation settings. It can go stale when inputs or policies change." },
  ]} />
  <P>When the run button offers <strong>Save version and run</strong>, it's asking to bind your edits to a version. Read the credibility message; an old validation may not cover a new scenario.</P>
</Section>

<Section id="what-reaches-the-engine" title="Saved isn't the same as simulated">
  <Callout tone="notsim">
    <p>Transport-family settings and routing flags can be saved and shown without being simulated. Disabled milestone controls describe planned support. The <DocLink to="supplier-stage">Supplier</DocLink>, <DocLink to="plant-stage">Plant</DocLink> and <DocLink to="customer-stage">Customer</DocLink> references mark each field.</p>
  </Callout>
  <P>The engine models one focal production stage; a multi-level BOM display doesn't add sub-assembly capacity or work in progress. After a significant change, read the conversion notes and effective values.</P>
  <P><strong>Version history › Export</strong> maps a saved policy through the same path as a run. Its Read me sheet says whether it used the latest run's dataset and scenario or the current project data — check that before treating it as evidence for a particular run.</P>
  <P>Next: <DocLink to="policy-versions-and-presets">versions and presets</DocLink>, then <DocLink to="model-validation">model validation</DocLink>.</P>
</Section>
</>; }

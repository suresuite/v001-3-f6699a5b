// Getting started — Uploading data (journey page, WP 5.2a redesign).
//
// Task first: the steps lead, explanation follows, and the natural keys are
// read from the contract (`RowKeyTable`) rather than listed by hand. Every
// section id the old page carried is kept — `pageDepth.test.tsx` holds four of
// them, and the upload wizard and validation findings deep-link to the rest.

import {
  DocPageTitle, InShort, Section, P, Callout, Steps, Defs, QA, Details, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { RowKeyTable } from "@/components/docs/tableRef";

export default function Guide() { return <>
<DocPageTitle slug="uploading-data" />
<InShort items={[
  <>Upload one CSV per dataset from <strong>Project Manager › Upload Data</strong>. Start from that tab's template.</>,
  <>Nothing changes in your model until you accept the rows. Rows with errors are held back.</>,
  <>Uploading again updates rows with the same IDs — it never deletes the rows you left out.</>,
]} />

<Section id="where" title="Upload a file">
  <Flow
    caption="The upload path for a standard CSV. Nothing is accepted until step 3."
    highlight={2}
    items={[
      { kicker: "1", title: "Upload", detail: "file kept as sent" },
      { kicker: "2", title: "Review", detail: "rows checked and compared" },
      { kicker: "3", title: "Promote", detail: "reviewed rows accepted" },
      { kicker: "4", title: "Verify", detail: "check the model" },
    ]}
  />
  <Steps steps={[
    { title: "Open Upload Data", where: "/project-manager", body: <>In <AppLink to="/project-manager">Project Manager</AppLink>, select the project you mean to change and choose <strong>Upload Data</strong>.</> },
    { title: "Pick the dataset tab and download its template", where: "Upload Data", body: <>Use CSV, one dataset per file. Renaming an XLSX file to .csv does not convert it. The template is a filled example: overwrite the rows, keep the headers. The deep-tier network also has a JSON path with different handling.</> },
    { title: "Upload, then read the review", where: "Review", body: <>Every row lands in one of five groups: <strong>new</strong>, <strong>changed</strong>, <strong>unchanged</strong>, <strong>superseded</strong> or <strong>held</strong>. Open a row to see the value you sent beside the value that was parsed.</>, check: <>a count for each group, and held rows listed with the finding that held them.</> },
    { title: "Choose Promote N rows to accept them", where: "Review", body: <>Rows with errors stay held. Fix them in the original CSV and upload it again — don't edit around them.</>, check: <>the accepted table shows the row counts you expected.</> },
  ]} />
  <DocFigure id="upload-review" />
  <Callout tone="tip" title="Practising first?">
    <p>Use the control-unit files from <DocLink to="your-first-project">Your first project</DocLink>. They are small enough to check by eye.</p>
  </Callout>
</Section>

<Section id="dependencies" title="Which file does what">
  <P>Item lists <em>describe</em> things. The BOM and the two logistics files <em>connect</em> them. A model that can run needs both kinds, plus economics, demand and capacity — having every table present is not the same as being ready to run.</P>
  <Defs items={[
    { term: "Item lists", def: <>Suppliers, Materials, Products and Customers. Their IDs must match the BOM and logistics files exactly, after trimming spaces. A supplier on its own creates no supply relationship.</> },
    { term: "BOM", def: <>How much of each material one product uses — units per unit, not a percentage. In the tutorial, P-CONTROL uses 1 M-BOARD and 2 M-CASE.</> },
    { term: "Inbound logistics", def: <>Which supplier delivers which material. <Term>volume</Term> is a rate in <Term>time_unit</Term>; <Term>lead_time</Term> has its own <Term>lead_time_unit</Term>.</> },
    { term: "Outbound logistics", def: <>Which customer buys which product. <Term>volume</Term> and <Term>time_unit</Term> set the demand rate; <Term>unit_price</Term> is the selling price. Product-level and customer/product overrides may change the demand the simulation uses.</> },
    { term: "Optional", def: <>Node locations (for maps), deep-tier firms (for exploration) and a multi-level BOM (for projects set up for one). None of these proves an upstream relationship or adds a production stage.</> },
  ]} />
</Section>

<Section id="what-is-checked" title="If something goes wrong">
  <QA items={[
    { q: "A number was rejected", a: <>Use a decimal point. Currency signs and thousands separators are not removed for you.</> },
    { q: "A header wasn't recognised", a: <>An extra column doesn't add a new parameter to the simulation. Check the dataset's reference page for the columns it accepts.</> },
    { q: "A blank cell was filled in", a: <>A blank optional cell supplies no value and may trigger a default. Required headers and required values are separate checks.</> },
    { q: "A zero was refused", a: <>Some fields accept 0 and some don't. BOM consumption must be above zero; a customer priority of 0 is allowed and means lowest priority.</> },
    { q: "The comparison isn't ready", a: <>Until the review has compared rows, don't read them as all new. Recompute the comparison, then decide.</> },
    { q: "There's no Promote button", a: <>That is usually your project rights, not the file. Send the project owner the exact message and the project name — uploading again won't help.</> },
  ]} />
  <Callout tone="warning" title="A warning doesn't stop a row">
    <p>An inbound <Term>unit_price</Term> of 0 is accepted with a warning, and the simulation reads it as 1.0. Read the warnings before you accept, and check the held rows even when the promotion succeeds.</p>
  </Callout>
</Section>

<Section id="uploading-twice" title="Uploading the same file again">
  <P>Rows with the same IDs are <strong>updated</strong>, and new IDs are <strong>added</strong>. Rows you leave out of the new file are <strong>not deleted</strong>. A blank cell is not a reliable “keep the old value” — if you mean to keep a value, include it.</P>
  <RowKeyTable
    caption="The columns that identify a row, read from the data contract. Same key means update; a new key means insert."
    tables={["bom_single_level", "inbound_logistics", "outbound_logistics", "materials", "products", "suppliers", "bom_multi_level", "demand_forecasts"]}
  />
  <Details title="How this works: which columns identify a row">
    <p>Each dataset has a <DocLink to="glossary#natural-key">natural key</DocLink> — the IDs that pick out one row within your project. Multi-level BOM and forecast files add hierarchy or period fields to it, so they are not interchangeable with a single-level BOM or static demand.</p>
    <p>The node list and the deep-tier network use a separate upload path with no review step. Don't assume they keep the raw file or replace rows the same way — export a copy and read the network-table page before you replace them.</p>
    <p>A column one row supplies is written for every row in that upload, which is why a blank cell can still change a value.</p>
  </Details>
</Section>

<Section id="what-happens-after" title="After you accept">
  <P>Check the accepted table, refresh derived data if you're asked to, then run <DocLink to="verify-your-inputs">input verification</DocLink>. Check relationships as well as counts: two rows with the wrong IDs still describe the wrong model.</P>
  <P>Re-validate your policies after a data change. Results from before the upload still describe the earlier inputs. An upload error, a row that fails validation and a permission denial need different fixes — capture the exact message.</P>
  <P>Never delete the project to fix one bad file. Next: <DocLink to="how-your-data-flows">follow a file through its life</DocLink>, or open the <DocLink to="data-model">field references</DocLink>.</P>
</Section>
</>; }

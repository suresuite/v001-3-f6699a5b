// §6.3 section 5 — the provenance dots. Written once; the dots themselves are
// imported from the grid's own PROVENANCE map, so the legend on this page and
// the legend under the grid cannot disagree.
//
// This page is §5.3 T2 made readable: "substitution is always visible, at the
// point of display, not in a log". A user who cannot decode the dot is a user
// for whom T2 is not met.

import { PageTitle, InShort, Section, P, Key, Callout, Steps, DocTable, Term, DocLink, AppLink, Provenance, Prose } from "@/components/docs/prose";
import { buildValueChain, VALUE_CHAIN_REMEDY } from "@/lib/trust/valueChain";
import { DocFigure } from "@/components/docs/DocFigure";
import { PROVENANCE, type Provenance as ProvenanceKind } from "@/components/policies/policyGridUi";

/** Reader-facing order: what came from you, then what we worked out, then what we assumed. */
const ORDER: ProvenanceKind[] = [
  "edited",
  "override",
  "data",
  "master",
  "suggested",
  "derived",
  "imputed",
  "contract" as ProvenanceKind,
  "default",
];

const MEANING: Partial<Record<string, string>> = {
  edited: "You have just changed this and not saved yet. Nothing else has seen it.",
  override: "You changed this and saved it. It stays until you remove it, and a re-upload does not touch it.",
  data: "It came from a file you uploaded, unchanged.",
  master: "It came from one of your item master files — materials, products or suppliers.",
  suggested:
    "We ranked your uploaded volumes and put the leader here. It is a starting point, not something you told us — confirm it.",
  derived:
    "We worked it out from your other uploads, because the field it belongs to was empty. The number is real; the choice to use it was ours.",
  imputed: "An average across your project stood in for a value nothing supplied. Verify these.",
  contract:
    "The cell is empty, and empty MEANS something here. The token shown is the declared meaning, not a number we invented.",
  default: "Nothing in your data resolved it, so the policy bundle's default applies.",
};

/**
 * A worked chain: the tutorial's S-BOARD → M-BOARD lead time, as the popover
 * builds it for an upload that went through review. The upload is illustrative
 * (names, file and times are made up); every label, sentence and absence is
 * produced by `buildValueChain`, the function the popover itself calls.
 */
const EXAMPLE = buildValueChain({
  row: {
    has_provenance: true, project_id: "example", target_table: "inbound_logistics", source_kind: "csv",
    original_filename: "inbound_logistics.csv", content_sha256: null, byte_size: 182, source_row_number: 2,
    raw: { supplier_id: "S-BOARD", material_id: "M-BOARD", lead_time: "2", lead_time_unit: "weeks" },
    parsed: { supplier_id: "S-BOARD", material_id: "M-BOARD", lead_time: 2, lead_time_unit: "weeks" },
    findings: [], diff_state: "new",
    uploaded_by_name: "Ana Analyst", uploaded_by_email: null, received_at: "2026-10-01T09:00:00Z",
    promoted_by_name: "Pat Planner", promoted_by_email: null, promoted_at: "2026-10-01T09:20:00Z",
    run_status: "promoted", later_uploads: 0, latest_upload_at: null,
  },
  dataset: "inbound_logistics",
  column: "lead_time",
  stage: "supplier",
  field: "lead_time_weeks",
  provenance: "data",
  displayed: "2",
  uploadable: true,
});

export default function WhereANumberCameFrom() {
  const dots = ORDER.filter((k) => PROVENANCE[k]);

  return (
    <>
      <PageTitle lead="Every number in the grid carries a mark saying where it came from. This is how to read them.">
        Where a number came from
      </PageTitle>
      <InShort items={[
        <>The coloured dot on a /policies cell says what <em>kind</em> of number it is: yours, worked out, or assumed.</>,
        <>Click the dot for the whole chain — file, row, who uploaded and promoted it, unit, what the engine does with it, and what would change it.</>,
        <>An unmarked cell is the bundle default. A step the system cannot answer says “unknown” and why; it is never left out.</>,
      ]} />

      <Section id="the-promise" title="The promise this keeps">
        <Key>
          No number without a source. Every value you see resolves to your data, a named rule, or an
          explicit default — there is no fourth possibility, and the mark tells you which.
        </Key>
        <P>
          The mark is on the cell, not in a log. That is deliberate: a substitution you would have
          to go looking for is a substitution most people never find, and a model built on numbers
          nobody checked is the failure this product is designed around.
        </P>
              <DocFigure id="provenance-dots" />
      </Section>

      <Section id="the-dots" title="The marks">
        <div className="divide-y divide-border rounded-sm border border-border bg-card shadow-xs">
          {dots.map((k) => {
            const { color, title } = PROVENANCE[k];
            return (
              <div key={k} className="grid grid-cols-1 gap-1 p-4 md:grid-cols-[13rem_minmax(0,1fr)] md:gap-4">
                <dt className="flex items-center gap-2 text-sm font-medium text-foreground">
                  <span
                    aria-hidden
                    className="inline-block h-2 w-2 flex-none rounded-full border border-border"
                    style={color ? { background: color } : undefined}
                  />
                  {title}
                  {!color && <span className="text-[11px] text-muted-foreground">(no dot)</span>}
                </dt>
                <dd className="min-w-0 text-sm leading-relaxed text-muted-foreground">
                  {MEANING[k] ?? title}
                </dd>
              </div>
            );
          })}
        </div>
      </Section>

      <Callout tone="limit" title="One of them has no dot, and that is a real gap">
        <p>
          A bundle default renders with no mark at all. So a cell showing a number nothing in your
          data produced looks exactly like a cell showing a number you supplied — unless you know
          that an unmarked cell is the default case.
        </p>
        <p>
          It is the most common state in a new project, which is the argument for not colouring it,
          and it is the state a careful reader most needs to see, which is the argument against. We
          are naming it here rather than letting the legend imply every substitution is visible.
        </p>
      </Callout>

      <Section id="check-a-value" title="Check one value, end to end">
        <Steps steps={[
          { title: "Find the cell", where: "/policies", body: <>Open the stage the field belongs to and find the row. The dot sits beside the value.</> },
          { title: "Click the dot", where: "the cell's dot", body: <>A panel opens with the value's chain. It is a panel rather than a tooltip so you can read it on a phone and copy from it.</> },
          { title: "Read every step, including the unknowns", where: "value chain", body: <>A step that cannot be answered says so and why — most often because the row was loaded before uploads were recorded. Unknown is not the same as “there was none”.</>, check: "a source file and row for an uploaded value, or a clear statement of why there isn't one." },
        ]} />
        <DocTable
          caption="The tutorial's S-BOARD → M-BOARD lead time, as the panel shows it — produced by the panel's own code from an illustrative upload."
          head={["Step", "Shows"]}
          rows={EXAMPLE.steps.map((st) => [
            <Prose text={st.label} />,
            st.value != null ? <Prose text={st.value} /> : <span className="text-gray-600"><Prose text={st.absentBecause ?? "not recorded"} /></span>,
          ])}
        />
        <P><Prose text={EXAMPLE.headline} /></P>
      </Section>

      <Section id="change-it" title="What would change it">
        <P>The last step of every chain names the one action that would change the value. It depends only on the mark:</P>
        <DocTable
          caption="The remedy for each mark — read from the value-chain code."
          head={["Mark", "To change the value"]}
          rows={dots.map((k) => [PROVENANCE[k].title, VALUE_CHAIN_REMEDY[k as keyof typeof VALUE_CHAIN_REMEDY] ?? "—"])}
        />
        <P>An overridden cell also offers <strong>Reset to master</strong>, which removes your /policies override and shows the item-master or lane-derived value again — the master itself was never changed.</P>
      </Section>

      <Section id="empty-means-something" title="When empty is an answer">
        <P>
          A few columns mean something specific when they are blank. A supplier with no{" "}
          <Term>capacity_per_week</Term> is an <em>unlimited</em> supplier, not one that can ship
          nothing. Those cells render the declared token with its own mark rather than a made-up
          number — because rendering <Term>0</Term> there tells the reader the exact inverse of what
          the model believes.
        </P>
        <P>
          <DocLink to="suppliers">Suppliers</DocLink> has the full story of that one, including
          where the grid still gets it wrong.
        </P>
      </Section>

      <Section id="related" title="Related">
        <P>
          <DocLink to="when-a-value-is-missing">When a value is missing</DocLink> — every
          substitution the system will make ·{" "}
          <DocLink to="how-policies-work">How policies work</DocLink> ·{" "}
          <DocLink to="what-happens-to-your-data">What happens to your data</DocLink>
        </P>
        <P>
          The legend also sits under the grid itself at <AppLink to="/policies">/policies</AppLink>,
          and it is the same list — this page reads it rather than copying it.
        </P>
      </Section>

      <Provenance from="the policy grid's own provenance map" />
    </>
  );
}

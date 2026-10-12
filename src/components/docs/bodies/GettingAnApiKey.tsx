// Developer API — Getting an API key (journey page, WP 5.2a redesign).
//
// Create, prove with a read, then write. The eight empty anchors are the old
// page's deep links and are kept so those links still land on this page; they
// should each move onto the section that now holds their content (flagged in
// the redesign audit, §5 item 5 — not moved silently).

import {
  DocPageTitle, InShort, Section, P, Steps, QA, Details, DocTable, Code, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

export default function Guide() { return <>
<DocPageTitle slug="getting-an-api-key" />
<span id="environments" />
<span id="losing-one" />
<span id="notebook" />
<span id="personal-keys" />
<span id="related" />
<span id="scopes" />
<span id="what-a-key-is" />
<span id="who-can-create" />
<InShort items={[
  <>Create the key in <strong>Developer API › API keys</strong>. Copy the secret now — you won't see it again.</>,
  <>Give it only the projects and scopes it needs, and an expiry.</>,
  <>Prove it works with a read before you let it write.</>,
]} />

<Section id="creating-one" title="Create a key">
  <Steps steps={[
    { title: "Open API keys", where: "/developer", body: <><AppLink to="/developer">Developer API</AppLink> › <strong>API keys</strong> › <strong>New key</strong>. You need key-management access.</> },
    { title: "Name it for its job", where: "New key", body: "Pick test or live, restrict it to the projects and scopes it needs, and set an expiry." },
    { title: "Copy the secret", where: "New key", body: "It's shown once. Later views show only a prefix.", check: "the key in your list, showing its prefix, scopes and expiry." },
  ]} />
  <DocFigure id="api-request" />
  <DocTable
    caption="Scopes used in this guide."
    head={["Scope", "Allows"]}
    rows={[
      [<Term>read:data</Term>, "Listing projects and reading data — the first request"],
      [<Term>read:policies</Term>, "Listing saved policy versions"],
      [<Term>read:runs</Term>, "Listing scenarios, polling a run, fetching replications"],
      [<Term>write:runs</Term>, "Creating a scenario or submitting a run"],
    ]}
  />
  <Details title="What a key can and can't do">
    <p>Keys carry an organization and optional project restrictions. What a key can reach also depends on its owner's current eligibility — a stored scope list isn't a permanent entitlement. <Term>GET /key</Term> returns the scopes the key may use now; the notebooks check it before they start.</p>
    <p>The test/live label controls limits. It isn't proof that the key points at a separate database.</p>
  </Details>
</Section>

<Section id="first-request" title="Make your first request">
  <P>Set <Term>SURESUITE_API_BASE</Term> (your gateway URL, ending in <Term>/functions/v1/api/v1</Term>) and <Term>SURESUITE_API_KEY</Term> in your local environment. Never commit the secret. This request needs <Term>read:data</Term>.</P>
  <Code>{`curl --fail-with-body \\
  -H "Authorization: Bearer $SURESUITE_API_KEY" \\
  "$SURESUITE_API_BASE/projects?limit=10"`}</Code>
  <P>Success is a <Term>data</Term> array and a <Term>next_cursor</Term>. A key that can see no projects gets a valid empty page:</P>
  <Code>{JSON.stringify({ data: [], next_cursor: null }, null, 2)}</Code>
  <P>Follow <Term>next_cursor</Term> until it's null. An empty <Term>data</Term> array is not a simulation result. The request and response shape are checked against the current handler; this guide doesn't claim a live authenticated request was run.</P>
</Section>

<Section id="submit" title="Submit a run">
  <Steps steps={[
    { title: "Find real IDs", where: "read:policies · read:runs", body: "List saved policy versions and scenarios in the authorized project. Don't copy example UUIDs into production." },
    { title: "POST the run", where: "write:runs", body: <>POST to <Term>/projects/PROJECT_ID/runs</Term> with <Term>scenario_id</Term> and <Term>policy_version_id</Term>. Leave <Term>acknowledge_warnings</Term> and <Term>force_rerun</Term> false unless you mean them. Set a unique <Term>Idempotency-Key</Term>, and reuse it only to retry this same request.</> },
    { title: "Poll until it's done", where: "read:runs", body: <>A <Term>run_id</Term> and status means accepted, not finished. Poll <Term>GET /runs/RUN_ID</Term>, then fetch <Term>GET /runs/RUN_ID/replications</Term>.</>, check: "status done, the versions you expected, the replication count, and the conversion notes." },
  ]} />
  <Code>{JSON.stringify({ scenario_id: "UUID_FROM_SCENARIO_LIST", policy_version_id: "UUID_FROM_POLICY_VERSION_LIST", acknowledge_warnings: false, force_rerun: false }, null, 2)}</Code>
</Section>

<Section id="errors" title="If a request fails">
  <QA items={[
    { q: "401", a: "Missing, malformed, expired or revoked key. Check the error code and replace the key in Developer API. Never paste a key into a support message." },
    { q: "403 or 404", a: "A missing scope, or a project or run the key can't reach. A 404 can deliberately hide something inaccessible." },
    { q: "400 or a validation response", a: "Read the error body for malformed IDs, unsupported fields or invalid input. Run-readiness findings mean fixing the model, not the auth header." },
    { q: "409 reuse_available", a: "A compatible result already exists. Inspect it; force a rerun only when you really want fresh computation." },
    { q: "429 or 503", a: "Quota, rate limit or a service that's down. Respect any retry information, retry a bounded number of times, and keep the same idempotency key." },
  ]} />
  <P>Keep the response's <Term>X-Request-Id</Term> and error code for diagnosis. Details: <DocLink to="endpoints-and-schemas">Endpoints &amp; schemas</DocLink> and <DocLink to="rate-limits-and-idempotency">rate limits and idempotency</DocLink>.</P>
</Section>
</>; }

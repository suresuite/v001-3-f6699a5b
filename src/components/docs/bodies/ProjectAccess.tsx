// Access & administration — Project access (guide).
//
// Who can do what on one project, how a role is given, and what a refused
// button says. The role matrix is the generated seed (`ProjectRoleMatrix`), the
// refusal sentences are `projectRightRefusal`'s own output for each case, and
// the membership and delegation rules are the database functions'
// (`admin_set_project_member`, `grant_project_delegation`,
// `project_rights_for_user`) — described, not restated as numbers.

import { PROJECT_RIGHT_LABELS, projectRightRefusal, type ProjectRight, type ProjectRights } from "@/lib/auth/projectRightsText";
import { PROJECT_ROLES, PROJECT_ROLE_DEFAULTS } from "@/lib/capabilities.generated";
import {
  DocPageTitle, InShort, Section, P, Callout, Steps, Defs, DocTable, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { ProjectRoleMatrix } from "@/components/docs/accessDocs";

const RIGHTS = Object.keys(PROJECT_RIGHT_LABELS) as ProjectRight[];
/** The lowest-ranked role whose default grants `right` — read from the seed. */
const lowestRole = (right: string) => {
  const r = [...PROJECT_ROLES].reverse().find((role) =>
    PROJECT_ROLE_DEFAULTS.some((g) => g.projectRole === role && g.capabilityKey === right && g.allowed));
  return r ? r.charAt(0).toUpperCase() + r.slice(1) : null;
};

/** One person's rights, shaped as the database returns them — for the refusal examples. */
const rights = (o: Partial<ProjectRights> & { decided?: ProjectRights["decisions"] }): ProjectRights => ({
  account_active: true, visible: true, can_edit_project: false, may_land_uploads: false,
  capabilities: {}, resolved_capabilities: {}, effective_role: null, is_modeler: false,
  decisions: o.decided, ...o,
});
const decision = (decided_by: "project_role" | "account_role" | "person_override", project_role: string | null, account_role = "user") => ({
  allowed: false, decided_by, project_role, project_grant: false, account_role, account_allows: false,
  account_source: "account_role" as const, person_override: decided_by === "person_override" ? false : null,
});
const REFUSALS: { when: string; text: string | null }[] = [
  { when: "An Analyst tries to edit a policy", text: projectRightRefusal("data_edit_policies", rights({ effective_role: "analyst", decided: { data_edit_policies: decision("project_role", "analyst") } })) },
  { when: "A Viewer tries to run a simulation", text: projectRightRefusal("simulation_lab", rights({ effective_role: "viewer", decided: { simulation_lab: decision("project_role", "viewer") } })) },
  { when: "No role on the project at all", text: projectRightRefusal("export", rights({ decided: { export: decision("account_role", null, "user") } })) },
  { when: "An administrator switched the right off for you", text: projectRightRefusal("export", rights({ effective_role: "editor", decided: { export: decision("person_override", "editor") } })) },
  { when: "The role allows uploads, the upload gate does not", text: projectRightRefusal("data_edit_inputs", rights({ effective_role: "analyst", resolved_capabilities: { data_edit_inputs: true }, may_land_uploads: false })) },
  { when: "The account is deactivated", text: projectRightRefusal("simulation_lab", rights({ account_active: false })) },
  { when: "Your rights could not be read", text: projectRightRefusal("simulation_lab", null) },
];

export default function ProjectAccessGuide() {
  return (
    <>
      <DocPageTitle slug="project-access" />
      <span id="members" />
      <span id="related" />
      <span id="why-separate" />
      <InShort items={[
        <>What you may do on a project is decided by your <strong>project role</strong> — Owner, Editor, Analyst or Viewer — not by your account label.</>,
        <>Check your role and every right, with the reason, on <strong>Profile › My organization</strong>.</>,
        <>Ask for the right your task needs. A super admin sets project roles; the person who creates a project owns it.</>,
      ]} />

      <Section id="roles" title="What each project role allows">
        <ProjectRoleMatrix caption="The default rights of each project role — read from the database's seed." />
        <P>These are defaults. A super admin holds every right everywhere, and an administrator can switch one right off for one person; both are named as the reason when they apply. An editor's four rights do not make them the owner: renaming, transferring or deleting the project are separate checks.</P>
        <Flow
          caption="How you come to hold a role. The highest one you hold applies."
          items={[
            { kicker: "automatic", title: "You created it", detail: "you are its Owner" },
            { kicker: "standing", title: "Membership", detail: "set by a super admin, optionally until a date" },
            { kicker: "temporary", title: "Delegation", detail: "always has an end date" },
          ]}
        />
        <DocFigure id="project-access-review" />
      </Section>

      <Section id="check" title="See your role and rights">
        <Steps steps={[
          { title: "Open My organization", where: "/profile", body: <>On <AppLink to="/profile">your profile</AppLink>, open <strong>My organization</strong>. It lists the projects of the organization you are working in, everyone on them, their role and each right — the same answer the app's buttons read.</> },
          { title: "Switch organization if the project isn't there", where: "/profile", body: <>Rights are stated as you hold them while working in the project's organization. If you belong to several, switch to the project's own first; the tab says when you are working in another one.</> },
          { title: "Read the reason on a refused button", where: "anywhere", body: <>A disabled control says which layer decided — your project role, your account role, an administrator's switch, the upload gate, or a suspended account.</>, check: "your role on the project and, for each right you lack, the sentence below that matches it." },
        ]} />
        <DocTable
          caption="What a refused button says — produced by the same function the app calls."
          head={["Situation", "The message"]}
          rows={REFUSALS.map((r) => [r.when, r.text ?? "allowed"])}
        />
        <Callout tone="note" title="The upload gate">
          <p><strong>Edit Input Data</strong> also needs the project's upload gate: uploads are accepted only from the project's owner, an Editor or Owner on it, or an app admin. A role that allows editing inputs on paper does not get past it alone.</p>
        </Callout>
      </Section>

      <Section id="ask" title="Ask for the right access">
        <Defs items={[
          { term: "Say the task", def: <>“Edit input data for <Term>Control-unit tutorial</Term> until Friday” is a request someone can grant. “Make me an admin” is not.</> },
          { term: "Ask for the lowest role that does it", def: <>{RIGHTS.map((r) => `${PROJECT_RIGHT_LABELS[r]}: ${lowestRole(r) ?? "no role grants it by default"}`).join(" · ")}.</> },
          { term: "Say how long", def: "A membership can end on a date, and a delegation always does — ask for the time the task needs." },
        ]} />
        <P>Who grants it: a super admin sets project roles at <AppLink to="/admin/projects">/admin/projects</AppLink> › <strong>Members &amp; access</strong> — choose the person, the <strong>Project role</strong>, and optionally <strong>Until</strong>, a date the membership lapses. The project's owner keeps a standing Owner role there; ownership moves only by transferring the project. An Admin or Owner of an organization can create projects in it and delete them, whatever their account role — see <DocLink to="roles-and-capabilities">Roles and capabilities</DocLink>.</P>
      </Section>

      <Section id="delegation" title="Delegation and expiry">
        <P>A delegation is temporary access one person passes to another. The database holds it to three rules:</P>
        <Defs items={[
          { term: "It must expire", def: "No end date, no delegation — and the date must be in the future." },
          { term: "It must say why", def: "A delegation with no rationale is refused." },
          { term: "It can't exceed the giver", def: "You can delegate up to your own role on the project, never above it." },
        ]} />
        <P>The person who gave it, anyone holding at least the delegated role on the project, or a super admin can revoke it. Administrators see live delegations on the Members &amp; access screen as <Term>delegated editor by … until …</Term>.</P>
        <Callout tone="warning" title="There is no screen to grant a delegation yet">
          <p>The rules above are enforced by the database, but no page in the app creates a delegation today. Ask a super admin for a membership with an <strong>Until</strong> date instead — it expires the same way.</p>
        </Callout>
        <P>When a role lapses, the project is not deleted and your work is not lost — ask the owner or an administrator to review the task. A session that worked yesterday is not proof the grant is still live.</P>
      </Section>

      <Section id="errors" title="When access and controls disagree">
        <P>Write down the project, the action, what My organization says, and the exact error. Reloading can fix a stale screen, but not a missing right. A missing button and a refused request are different evidence: send both.</P>
        <Callout tone="warning" title="Enforcement has known gaps">
          <p>The source does not establish the same enforcement on every browser and backend path. The browser simulation dispatch gap is described in <DocLink to="roles-and-capabilities">Roles and capabilities</DocLink>. This page records it; it does not change access control or certify a live deployment.</p>
        </Callout>
        <P>Access to the manual is separate: not being able to open a section of these docs says nothing about your project role.</P>
      </Section>
    </>
  );
}

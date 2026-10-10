// What a project role allows, rendered from the seed rather than typed.
//
// `PROJECT_ROLE_DEFAULTS` is generated from the `project_role_capabilities`
// migrations, and the right names are the ones the app's buttons use
// (`projectRightsText.ts`). Roles & capabilities and Project access both render
// this; before it, the matrix was a hand-typed table on one of them.

import { PROJECT_ROLES, PROJECT_ROLE_DEFAULTS } from "@/lib/capabilities.generated";
import { PROJECT_RIGHT_LABELS, type ProjectRight } from "@/lib/auth/projectRightsText";
import { DocTable } from "@/components/docs/prose";

const RIGHTS = Object.keys(PROJECT_RIGHT_LABELS) as ProjectRight[];
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function ProjectRoleMatrix({ caption }: { caption: string }) {
  const allowed = (role: string, right: string) =>
    PROJECT_ROLE_DEFAULTS.find((g) => g.projectRole === role && g.capabilityKey === right)?.allowed;
  return (
    <DocTable
      caption={caption}
      head={["Project role", ...RIGHTS.map((r) => PROJECT_RIGHT_LABELS[r])]}
      rows={PROJECT_ROLES.map((role) => [
        cap(role),
        ...RIGHTS.map((r) => {
          const a = allowed(role, r);
          return a === undefined ? "not set" : a ? "Yes" : "No";
        }),
      ])}
    />
  );
}

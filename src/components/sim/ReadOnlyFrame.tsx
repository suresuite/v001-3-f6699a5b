import type { ReactNode } from "react";
import { Link } from "react-router-dom";

/** What the reader can do about the lock, in place — never a trip elsewhere. */
export interface ReadOnlyAction {
  label: string;
  onClick: () => void;
}

/**
 * Renders an editor read-only, with the reason on screen (WP 9.4 slice 4).
 *
 * A `<fieldset disabled>` disables every input, select and button inside it
 * natively, so no editor needs a read-only branch of its own — the controls are
 * the real ones, shown with the values the owner of the row set.
 *
 * `action` is the way out of the lock when there is one on this page (unlock
 * the model's protocol, start a scenario from the baseline). The Run & Validate
 * link is only for a lock /policies owns — sending a reader there to unlock a
 * setting this page can unlock left them nowhere to change it.
 */
export function ReadOnlyFrame({
  reason,
  action = null,
  validateLink = true,
  children,
}: {
  /** null renders the children untouched */
  reason: string | null;
  action?: ReadOnlyAction | null;
  /** show the Policies › Run & Validate link (the baseline's owner) */
  validateLink?: boolean;
  children: ReactNode;
}) {
  if (!reason) return <>{children}</>;
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-sm border border-[rgba(20,184,196,0.45)] bg-[rgba(20,184,196,0.07)] px-3 py-2 text-[12.5px] text-[#18181b]">
        <span className="min-w-0 flex-1 [text-wrap:pretty]">{reason}</span>
        {action ? (
          <button
            type="button"
            onClick={action.onClick}
            className="h-[30px] min-h-11 shrink-0 rounded-sm border border-foreground bg-foreground px-3 text-[12.5px] font-medium text-background md:min-h-0"
            data-testid="read-only-action"
          >
            {action.label}
          </button>
        ) : null}
        {validateLink ? (
          <Link
            to="/policies"
            className="inline-flex min-h-11 items-center text-[#0e7f88] underline-offset-2 hover:underline md:min-h-0"
          >
            Run &amp; Validate ›
          </Link>
        ) : null}
      </div>
      <fieldset disabled className="m-0 min-w-0 border-0 p-0 opacity-80">
        {children}
      </fieldset>
    </div>
  );
}

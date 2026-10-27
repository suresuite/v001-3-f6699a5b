// The one place a drawn edge's weight is summed and labelled (§4 D306). Moved to
// `supabase/functions/_shared/` so the product-level metrics analyzer reads the
// same graph the pages draw; re-exported here so no page import changes.
export * from '../../../supabase/functions/_shared/laneEdges.ts';

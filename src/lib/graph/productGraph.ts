// The PRODUCT-LEVEL graph (WP 8.4). Moved to `supabase/functions/_shared/` so the
// product-level metrics analyzer computes on exactly the graph this page draws;
// re-exported here so no page import changes.
export * from '../../../supabase/functions/_shared/productGraph.ts';

-- Các RPC này chỉ phục vụ worker dùng service_role, không mở cho app.
revoke execute on function public.increment_glossary_hits(bigint, text[])
  from public, anon, authenticated;
revoke execute on function public.lint_trend(bigint)
  from public, anon, authenticated;
revoke execute on function public.lint_drift_novels(numeric, integer)
  from public, anon, authenticated;

grant execute on function public.increment_glossary_hits(bigint, text[]) to service_role;
grant execute on function public.lint_trend(bigint) to service_role;
grant execute on function public.lint_drift_novels(numeric, integer) to service_role;

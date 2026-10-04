
    create policy "deny browser access to google oauth connections"
    on public.google_oauth_connections
    as restrictive
    for all
    to anon, authenticated
    using (false)
    with check (false);
  

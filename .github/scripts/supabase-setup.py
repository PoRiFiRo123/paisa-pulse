#!/usr/bin/env python3
"""Sets up the Supabase project for Paisa Pulse accounts, from CI.

Needs the SUPABASE_ACCESS_TOKEN secret (a personal access token from Supabase › Account › Access Tokens).
Optional: the SUPABASE_PROJECT_REF variable, if the account has more than one project.

1. Applies supabase/migrations/*.sql that haven't run yet (tracked in public._paisa_migrations).
2. Turns on email + password sign-in without confirmation emails (no emails are ever sent).
3. Writes the project URL and its public (publishable) key to $GITHUB_OUTPUT as `url` and `key`,
   for the Android and iOS builds. Both are public by design; the database is guarded by the
   functions in the migration.

Without the token it writes empty outputs, and the apps say accounts aren't set up in that build.
"""
import glob, json, os, sys, urllib.error, urllib.request

API = "https://api.supabase.com/v1"
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
OUT = os.environ.get("GITHUB_OUTPUT")


class SetupError(Exception):
    pass


def output(url="", key=""):
    if OUT:
        with open(OUT, "a") as f:
            f.write(f"url={url}\nkey={key}\n")


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
                                          "User-Agent": "paisa-pulse-ci"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        raise SetupError(f"Supabase API {method} {path} failed: HTTP {e.code} {e.read().decode()[:600]}")


def main():
    if not TOKEN:
        print("SUPABASE_ACCESS_TOKEN is not set: building without accounts.")
        return output()
    projects = call("GET", "/projects") or []
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not ref:
        if not projects:
            sys.exit("No Supabase projects on this account.")
        named = [p for p in projects if "paisa" in p.get("name", "").lower()]
        ref = (named or projects)[0]["ref"] if len(projects) == 1 or named else None
        if not ref:
            sys.exit("Several projects: set the SUPABASE_PROJECT_REF repository variable. Projects: "
                     + ", ".join(f"{p['name']} ({p['ref']})" for p in projects))
    print(f"Project: {ref}")

    def query(sql):
        return call("POST", f"/projects/{ref}/database/query", {"query": sql})

    query("create table if not exists public._paisa_migrations (name text primary key, applied_at timestamptz not null default now());"
          "alter table public._paisa_migrations enable row level security;")
    done = {r["name"] for r in (query("select name from public._paisa_migrations") or [])}
    root = os.path.join(os.path.dirname(__file__), "..", "..", "supabase", "migrations")
    for path in sorted(glob.glob(os.path.join(root, "*.sql"))):
        name = os.path.basename(path)
        if name in done:
            continue
        print(f"Applying {name}")
        sql = open(path).read()
        query(sql + f"\ninsert into public._paisa_migrations(name) values ('{name}');")

    # Email + password sign-in with no emails sent: new accounts are confirmed straight away.
    call("PATCH", f"/projects/{ref}/config/auth", {
        "external_email_enabled": True,
        "mailer_autoconfirm": True,
        "disable_signup": False,
    })

    keys = call("GET", f"/projects/{ref}/api-keys?reveal=true") or []
    key = next((k["api_key"] for k in keys if k.get("type") == "publishable" and k.get("api_key")), None) \
        or next((k["api_key"] for k in keys if k.get("name") == "anon" and k.get("api_key")), None)
    if not key:
        sys.exit("No publishable or anon key found for the project.")
    print("Database and sign-in are ready.")
    output(f"https://{ref}.supabase.co", key)


if __name__ == "__main__":
    # A setup problem shouldn't stop the app builds: they build without accounts and the run shows a warning.
    try:
        main()
    except (SetupError, SystemExit, OSError) as e:
        msg = str(e)
        if "401" in msg:
            msg += " -- the SUPABASE_ACCESS_TOKEN secret is wrong or revoked: make a new personal access token " \
                   "(Supabase > Account > Access Tokens, starts with sbp_) and save it as the secret."
        print(f"::warning title=Accounts not set up::{msg}")
        output()

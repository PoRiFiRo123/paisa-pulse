#!/usr/bin/env python3
"""Sets up the Supabase project for Paisa Pulse accounts, from CI.

Needs the SUPABASE_ACCESS_TOKEN secret (a personal access token from Supabase › Account › Access Tokens).
Optional: the SUPABASE_PROJECT_REF variable, if the account has more than one project.

1. Applies supabase/migrations/*.sql that haven't run yet (tracked in public._paisa_migrations).
2. Turns on email + password sign-in without confirmation emails, and, with the RESEND_API_KEY secret,
   sends password reset codes through Resend (from MAIL_FROM, default no-reply@nishitrk.tech).
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

    # Password reset emails through Resend (needs the RESEND_API_KEY secret and the sending domain
    # verified in Resend). The email carries a 6-digit code the app asks for; no links.
    resend = os.environ.get("RESEND_API_KEY", "").strip()
    if resend:
        sender = os.environ.get("MAIL_FROM", "").strip() or "no-reply@nishitrk.tech"
        code_mail = ("<h2>Reset your Paisa Pulse password</h2><p>Enter this code in the app:</p>"
                     "<p style=\"font-size:32px;font-weight:700;letter-spacing:6px\">{{ .Token }}</p>"
                     "<p>It works for an hour. If you didn't ask for it, ignore this email; your password stays the same.</p>")
        call("PATCH", f"/projects/{ref}/config/auth", {
            "smtp_host": "smtp.resend.com", "smtp_port": "465", "smtp_user": "resend", "smtp_pass": resend,
            "smtp_admin_email": sender, "smtp_sender_name": "Paisa Pulse",
            "mailer_otp_length": 6, "mailer_otp_exp": 3600,
            "mailer_subjects_recovery": "Your Paisa Pulse reset code",
            "mailer_templates_recovery_content": code_mail,
        })
        print(f"Password reset emails go out from {sender} through Resend.")
    else:
        print("RESEND_API_KEY is not set: no password reset emails.")

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

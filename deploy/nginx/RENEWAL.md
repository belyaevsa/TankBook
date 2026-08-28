# Certificate renewal for tankbook.live

**Status: renewal is automatic as of 2026-08-28** (W11). The certificate was
first issued with `certbot --manual` (DNS-01 by hand), which certbot said would
never renew, and was then re-issued over `--webroot` with `--cert-name` and a
reload `--deploy-hook`.

This file stays because the reasoning is needed again: at the next provider
change, the next server rebuild, or the first time a renewal quietly stops. The
verification section is the part to re-run, not the prose.

## The one thing to understand first

Certbot stores, per certificate, *how it was obtained* in
`/etc/letsencrypt/renewal/tankbook.live.conf`. `certbot renew` simply repeats
that recipe. A manual DNS challenge cannot be repeated unattended, which is why
certbot said it would not renew. **So the fix is not "turn renewal on" - it is
re-issuing the certificate with a method a machine can repeat**, which rewrites
that file.

## Path A - HTTP validation (recommended)

Works once DNS A/AAAA records point at this host and port 80 is reachable from
the internet. The nginx config already serves the challenge: the port-80 block
has `location ^~ /.well-known/acme-challenge/` with `root /var/www/certbot`, and
`^~` makes it win over the HTTPS redirect, so the challenge is never 301'd away.

First create the webroot and **prove nginx actually serves it**. Doing this
before certbot separates two failures that produce similar-looking errors: a
webroot nginx does not serve, and a domain whose DNS does not point at this
host. Certbot cannot tell you which it hit; this can.

```sh
sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
echo ok | sudo tee /var/www/certbot/.well-known/acme-challenge/probe >/dev/null

# From this host - proves nginx serves the webroot at all:
curl -s http://127.0.0.1/.well-known/acme-challenge/probe -H 'Host: tankbook.live'

# From the public internet - proves DNS points here AND port 80 is open.
# Run it for each name; every one must print "ok".
for d in tankbook.live api.tankbook.live; do
  printf '%s -> ' "$d"
  curl -s --max-time 10 "http://$d/.well-known/acme-challenge/probe" || echo FAILED
done

sudo rm -f /var/www/certbot/.well-known/acme-challenge/probe
```

If the local curl prints `ok` but a public one does not, the webroot is fine and
DNS or the firewall is the problem - do not re-run certbot until that is fixed,
because each failed attempt counts against Let's Encrypt rate limits.

```sh
sudo certbot certonly --webroot -w /var/www/certbot \
     -d tankbook.live -d api.tankbook.live \
     --cert-name tankbook.live \
     --deploy-hook "systemctl reload nginx" \
     --force-renewal
```

Three flags there are not decoration:

- **`--cert-name tankbook.live`** reuses the existing lineage. Without it certbot
  may create `tankbook.live-0001`, write the new certificate there, and leave
  nginx pointing at the old directory - so renewal "succeeds" for months while
  the served certificate quietly expires.
- **`--deploy-hook "systemctl reload nginx"`** reloads after each renewal. nginx
  reads certificates at startup and holds them; without this, renewal succeeds
  and the site keeps serving the **old** certificate until someone reloads by
  hand. This is the failure that looks most like everything working.
- **`--force-renewal`** makes certbot actually run the new challenge now rather
  than saying "not due for renewal" and leaving the old recipe in place. The
  point of the run is to exercise and record the new method, not to get fresh
  bytes.

## Path B - DNS validation, automated

Needed if port 80 is not publicly reachable, or if a wildcard is ever wanted
(wildcards are DNS-01 only). Requires an API at the DNS provider.

If certbot has a plugin for the provider, prefer it - `--dns-cloudflare`,
`--dns-route53`, and similar handle propagation waits themselves. Otherwise
supply hooks:

```sh
sudo certbot certonly --manual --preferred-challenges dns \
     -d tankbook.live -d api.tankbook.live \
     --cert-name tankbook.live \
     --manual-auth-hook /usr/local/bin/certbot-dns-auth.sh \
     --manual-cleanup-hook /usr/local/bin/certbot-dns-cleanup.sh \
     --deploy-hook "systemctl reload nginx" \
     --force-renewal
```

The auth hook receives `$CERTBOT_DOMAIN` and `$CERTBOT_VALIDATION`, creates
`_acme-challenge.$CERTBOT_DOMAIN` as a TXT record, **and must wait for the record
to be visible to a public resolver before returning** - returning too early is
the usual reason these hooks fail intermittently. The cleanup hook removes it.

## Verify - and this is the part that matters

```sh
# 1. The recipe actually changed. Expect authenticator = webroot (or dns-...),
#    NOT manual.
sudo grep -E 'authenticator|webroot_path|renew_hook' \
     /etc/letsencrypt/renewal/tankbook.live.conf

# 2. Rehearse the real thing. This performs a full challenge against the
#    staging server. If it fails, renewal is not fixed, whatever the config says.
sudo certbot renew --dry-run

# 3. Something must actually run it. One of these should exist and be active.
systemctl list-timers | grep -i certbot   # systemd
ls -l /etc/cron.d/certbot                 # or cron

# 4. Only one lineage - if you see tankbook.live-0001, --cert-name was missed
#    and nginx is pointing at the wrong directory.
sudo ls -1 /etc/letsencrypt/live/

# 5. What is actually being served, which is the only end-to-end proof:
echo | openssl s_client -connect tankbook.live:443 -servername tankbook.live 2>/dev/null \
  | openssl x509 -noout -dates -subject
```

**A renewal that has never been rehearsed is not a renewal.** `--dry-run`
succeeding is the check; a config that looks right is not. That is the same
standard the rest of this repo uses - exit codes and deliberate failures, not
appearances.

## After it works

Close `W11` in `docs/TASKS.md`, and record the date `certbot renew --dry-run`
last passed. If Path B is used, the hooks belong in version control too.

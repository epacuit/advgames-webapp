# Deploy: Netlify (frontend) + Hetzner VPS (backend)

```
Browser ── https://advgames.pacuit.org     ──▶ Netlify (static React bundle)
            │
            │ fetch() →
            ▼
Browser ── https://api.advgames.pacuit.org ──▶ Caddy (Hetzner VPS)
                                                 └─▶ 127.0.0.1:8080  (Julia + Oxygen)
```

- This directory is its own git repo (`advgames-webapp` on GitHub). The VPS
  deploys by `git pull`; Netlify deploys by watching the repo.
- The webapp is self-contained: the Julia sim files
  (`advgames.jl`, `advgames_network.jl`, `advgames_analysis.jl`,
  `base_params.jl`, `peer_selection.jl`) are snapshotted into
  `backend/sim/` by `./sync-sim.sh`. Re-run it whenever you edit those
  files at the upstream research repo and commit the updated snapshots.
- CORS on the backend allow-lists `https://advgames.pacuit.org` plus
  `localhost:5173` and `localhost:3000` for dev.

On the VPS the app lives at `/home/eric/apps/advgames` and runs as the
`eric` user (matching the convention for other apps on the box).

---

## Step 1 — DNS

On your `pacuit.org` DNS, add:

| Name | Type | Value | Purpose |
|---|---|---|---|
| `api.advgames` | A | `<VPS IP>` | backend (Caddy on Hetzner) |
| `advgames` | CNAME | `<netlify-site>.netlify.app` | frontend (set after Step 5) |

Verify: `dig +short api.advgames.pacuit.org`.

## Step 2 — VPS setup (as `eric`)

SSH to the VPS as `eric`. Install Caddy + Julia if not already there:

```sh
sudo apt update && sudo apt install -y \
  curl git build-essential ufw \
  debian-keyring debian-archive-keyring apt-transport-https

# Firewall (skip if already configured for other apps)
sudo ufw allow OpenSSH
sudo ufw allow http
sudo ufw allow https
sudo ufw --force enable

# Caddy — skip if you already installed it for the other apps
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

# Julia via juliaup (installed into eric's home)
curl -fsSL https://install.julialang.org | sh -s -- -y --default-channel release
# juliaup puts julia at ~/.juliaup/bin/julia; symlink it system-wide for systemd
sudo ln -sf "$HOME/.juliaup/bin/julia" /usr/local/bin/julia
julia --version
```

## Step 3 — Clone the repo

```sh
mkdir -p ~/apps
cd ~/apps
git clone https://github.com/epacuit/advgames-webapp.git advgames
cd advgames
```

## Step 4 — Julia deps + services

```sh
# Install Julia packages into eric's depot
(cd backend && julia --project=. -e 'using Pkg; Pkg.instantiate()')

# systemd unit + Caddy block
sudo cp deploy/advgames-sim.service /etc/systemd/system/
sudo bash -c 'cat deploy/Caddyfile.snippet >> /etc/caddy/Caddyfile'
sudo systemctl daemon-reload
sudo systemctl enable --now advgames-sim
sudo systemctl reload caddy

# Watch it come up (JIT warmup is ~30–60s on first boot)
sudo journalctl -fu advgames-sim
# ^C when you see "Serving on http://127.0.0.1:8080"
```

Sanity check from the VPS:

```sh
curl https://api.advgames.pacuit.org/health     # {"status":"ok"}
curl -i -H "Origin: https://advgames.pacuit.org" https://api.advgames.pacuit.org/health \
  | grep -i access-control
# expect: Access-Control-Allow-Origin: https://advgames.pacuit.org
```

## Step 5 — Netlify frontend

Two options.

### A. Git-linked site (recommended — auto-deploys on push)

1. Netlify → **Add new site → Import from Git** → pick `advgames-webapp`.
2. **Branch to deploy**: `main`
3. **Base directory**: `frontend`
4. **Build command**: `npm ci && npm run build`
5. **Publish directory**: type just `dist` — Netlify's form prepends the Base directory automatically, so the resolved value shown will be `frontend/dist`.
6. No env vars needed — `.env.production` already bakes `VITE_API_URL=https://api.advgames.pacuit.org` into the build.
7. Site settings → **Domain management** → add `advgames.pacuit.org`. Netlify gives you a CNAME target and (optionally) a TXT record for verification. Set the CNAME from Step 1.

### B. CLI deploy

```sh
(cd frontend && npm ci && npm run build)
npx netlify-cli deploy --dir=frontend/dist --prod
```

---

## Updating

**Both sides, from your laptop:**

```sh
# If you edited sim sources at the research-repo root:
./sync-sim.sh
# then commit the refreshed backend/sim/ files

git add -A && git commit -m "..." && git push
```

**VPS** (as `eric`):
```sh
cd /home/eric/apps/advgames && git pull && sudo systemctl restart advgames-sim
```

**Netlify** auto-builds on push if linked via Git.

> Want to skip the Netlify build for a backend-only commit? Put `[skip ci]` in the commit message.

## Logs & troubleshooting

```sh
sudo journalctl -fu advgames-sim         # Julia server
sudo tail -f /var/log/caddy/advgames-api.log
```

- **CORS error in browser**: check `SIM_CORS_ORIGINS` in the systemd unit — scheme + host, no trailing slash. Match exactly what the browser reports as the `Origin` header.
- **Cert not issued**: DNS hasn't propagated, or port 80/443 blocked. `sudo ufw status`.
- **First request slow**: JIT warmup; service logs "Warmup complete in …s" when ready.
- **Service won't start**: `sudo journalctl -u advgames-sim --since '5 min ago'` usually tells you (missing dep, path issue, etc.).

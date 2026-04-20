# Advocacy Games Webapp

Interactive companion to the Advocacy Games paper.

- **Frontend** (`frontend/`) — Vite + React + TypeScript + Recharts.
  Deployed as a static bundle to Netlify at https://advgames.pacuit.org.
- **Backend** (`backend/`) — Julia + Oxygen.jl wrapping the paper's
  simulation code without modification. Deployed on a Hetzner VPS behind
  Caddy at https://api.advgames.pacuit.org.

The `backend/sim/` directory is a **snapshot** of the paper's simulation
sources (`advgames.jl`, `advgames_network.jl`, `advgames_analysis.jl`,
`base_params.jl`, `peer_selection.jl`), refreshed by `./sync-sim.sh`.
The backend `include`s from `backend/sim/`; it never modifies or forks
the paper code.

## Directory layout

```
frontend/            # Vite + React — deploys to Netlify
  src/               # App.tsx, AnimationView.tsx, etc.
  .env.development   # VITE_API_URL=http://localhost:8080
  .env.production    # VITE_API_URL=https://api.advgames.pacuit.org
backend/             # Julia + Oxygen — deploys to Hetzner
  server.jl          # HTTP routes + CORS + warmup
  server_api.jl      # run_one() — the simulation handler
  server_validate.jl # request validation
  sim/               # snapshotted paper sources (populated by ../sync-sim.sh)
  Project.toml       # pinned Julia deps
  Manifest.toml      # exact resolved versions (committed for reproducibility)
sync-sim.sh          # copies paper sources into backend/sim/
deploy/              # systemd unit + Caddyfile snippet + deploy README
```

## Local development

**Backend:**

```sh
cd backend
julia --project=. -e 'using Pkg; Pkg.instantiate()'    # first time
julia --project=. -t auto server.jl
# Warmup takes ~30s on first boot (JIT), then logs "Serving on http://127.0.0.1:8080"
```

**Frontend:**

```sh
cd frontend
npm ci
npm run dev
# Open http://localhost:5173
```

`.env.development` points the frontend at `http://localhost:8080`; CORS
is pre-configured for `localhost:5173`.

## Refreshing the sim snapshot

When the upstream simulation sources at the research repo change:

```sh
./sync-sim.sh              # copies the 5 .jl files into backend/sim/
git add backend/sim && git commit -m "..."
```

## Deploying

See `deploy/README.md` for the full walkthrough (VPS setup, systemd,
Caddy, Netlify).

- **Frontend**: push to the repo; Netlify builds + deploys.
- **Backend**: `ssh eric@api.advgames.pacuit.org && cd /home/eric/apps/advgames && git pull && sudo systemctl restart advgames-sim`.

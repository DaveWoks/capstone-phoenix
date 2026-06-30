# Architecture

## 1. Topology diagram

```
Internet
   │
   │ DNS: taskapp.34.255.116.97.nip.io
   │ (a free service that turns this address into the control plane's IP)
   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Control Plane — ip-10-0-1-15 (eu-west-1a)                          │
│  Public IP: 34.255.116.97   Private IP: 10.0.1.15                   │
│                                                                       │
│  Traefik (built into k3s) — handles incoming traffic                │
│  cert-manager — gets a free HTTPS certificate from Let's Encrypt    │
│       │                                                              │
│       ├── "/"     goes to the frontend (the website)                │
│       └── "/api"  goes to the backend (the API)                     │
└───────┼────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────┐         ┌──────────────────────────┐
│ Worker 1 — ip-10-0-2-216 │         │ Worker 2 — ip-10-0-3-147 │
│ (eu-west-1b)             │         │ (eu-west-1c)             │
│                          │         │                          │
│ 1 frontend copy          │         │ 1 frontend copy          │
│ 1 backend copy           │         │ 1 backend copy           │
│ Database (Postgres)      │         │ (extra frontend copy)    │
└──────────────────────────┘         └──────────────────────────┘
```

I run 2 copies of the frontend and 2 copies of the backend. Kubernetes is told
to spread them out so no two copies of the same thing land on the same
machine. That way, if one machine goes down, there's always a working copy
somewhere else. The database only has 1 copy, and it's tied to a storage disk
so its data doesn't disappear if the database pod restarts.

## 2. Servers and network

- **3 servers total:** 1 control plane (the "brain" that manages everything) +
  2 worker servers (where the actual app runs). All are small AWS servers
  (`t3.small`) running Ubuntu.
  - Control plane: `34.255.116.97` (public), `10.0.1.15` (private)
  - Worker 1: `108.131.247.147` (public), `10.0.2.216` (private)
  - Worker 2: `18.201.188.97` (public), `10.0.3.147` (private)
- Each server is in a different "zone" (a separate physical data center inside
  AWS's Ireland region), so if one zone has a problem, the other two are
  unaffected.
- **What's open to the internet (firewall rules):**
  - Port `22` (SSH, for me to log in) — only my own computer's IP can connect.
  - Ports `80` and `443` (website traffic) — open to everyone, since this is a
    public website.
  - Port `6443` (the Kubernetes control panel) — **NOT** open to the public
    internet. Only the 3 servers can talk to each other on this port. This
    matters because if this port were open to everyone, anyone could try to
    take control of my cluster.
  - A few other ports (`10250`, `8472`, `51820`) that Kubernetes uses
    internally between the 3 servers — also not open to the public.

## 3. How a request flows through the system

1. Someone types `taskapp.34.255.116.97.nip.io` in their browser.
2. That address automatically points to my control plane's IP (nip.io is a
   free trick that turns any IP address into a usable web address, so I
   didn't have to buy a domain).
3. The request arrives at Traefik (the traffic router built into k3s) over
   HTTPS, using a real, trusted certificate from Let's Encrypt.
4. If the web address starts with `/`, Traefik sends it to the frontend
   (the website the user sees).
5. If it starts with `/api`, Traefik sends it to the backend (the part that
   handles logins and tasks).
6. The backend talks to the database using its internal name `postgres` —
   it doesn't need to know any IP addresses, Kubernetes handles that.
7. The database saves data to a storage disk that stays attached even if the
   database restarts.

## 4. Problems that only show up once you stop using a single server

| On one server, this was fine... | ...but breaks once you have multiple servers/copies | How I fixed it |
|---|---|---|
| The app set up the database automatically when it started | If 2 or more copies of the backend start at the same time, they'd both try to set up the database at once and conflict with each other | I made a separate one-time task (a "Job") that creates the demo login accounts. It only runs once, checks if accounts already exist first, and won't cause conflicts |
| Saving files directly on the one server's hard disk | If the app moves to a different server, the files saved on the old server are gone | The database uses a separate storage disk that follows it around, not tied to any one server. I tested this by deleting the database's pod and confirming the data was still there afterward |
| The app published itself on one fixed port on one server | With 3 servers and several copies of each part, there's no single fixed address anymore | I set up one single "front door" (Traefik) that automatically finds whichever working copy should handle each request, no matter which server it's on |
| If the app crashed, I'd have to notice and restart it manually | If a server itself goes down, there's nothing to restart, since the app is gone with it | I told Kubernetes to constantly check if each piece of the app is healthy. If a piece crashes or a whole server dies, Kubernetes automatically starts a new copy somewhere else. I proved this works by deliberately disabling one of the 3 servers and watching the app stay online |
| One copy of the app handled all traffic | If lots of people use the app at once, one copy gets overloaded | I set up auto-scaling on the backend so when it gets busy, Kubernetes automatically creates more copies (up to 6), then shrinks back down once things calm down. I tested this by generating fake heavy traffic and watched it scale up live |
| Passwords and secrets were saved in a plain text file on the server | This file could accidentally get uploaded to GitHub for anyone to see | All passwords and secret keys are stored in a Kubernetes "Secret," which I created separately and never put in my GitHub repo |
| Nothing stopped one part of the app from talking to another part it shouldn't | With more moving pieces, a bug or attacker in one part could reach parts it has no business touching | I set up rules so the database can only be reached by the backend, the backend can only be reached by the frontend, and everything is blocked by default unless I specifically allow it. (Note: I've written these rules, but the basic networking tool that comes with k3s doesn't actually enforce them yet — I'd need to install an upgraded networking tool to make these rules active. I'm being upfront about this gap rather than hiding it) |

## 5. Decisions I made and why

- **Plain Kubernetes files instead of Helm or Kustomize:** I'm running one app
  in one place, so the extra tooling that Helm/Kustomize offer (mainly useful
  for managing many environments) wasn't worth learning under a 3-week
  deadline.
- **Used k3s's built-in traffic router (Traefik) instead of installing a
  different one (ingress-nginx):** it already comes with k3s and worked
  immediately with my free HTTPS certificates, so there was no reason to swap
  it out.
- **Used k3s's default networking instead of a more advanced one:** this is
  the trade-off mentioned above — my security rules for "who can talk to who"
  are written but not yet actively enforced, because that requires swapping
  out k3s's basic networking tool.
- **No domain name purchased:** I used a free service called nip.io that turns
  any server IP address into something that works just like a real domain
  name, including getting a real HTTPS certificate. This let me skip paying
  $10-15 for a domain.
- **One website address instead of two (one for the site, one for the API):**
  the frontend already calls `/api` on whatever address it's loaded from, so
  there was no need to set up and secure a second address just for the API.
- **Secrets kept separate from my code:** I never typed passwords into any
  file that gets uploaded to GitHub. Instead I created them directly inside
  Kubernetes, separately from my repo.

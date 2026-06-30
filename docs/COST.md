# Cost

## What I'm actually paying for

| Item | What it is | How many | Cost per month |
|---|---|---:|---:|
| Control plane server | 1 small AWS server (`t3.small`) that manages the cluster | 1 | ~$15 |
| Worker servers | 2 small AWS servers (`t3.small`) that run the actual app | 2 | ~$30 |
| Storage disk for the database | A small disk (5GB) attached to the database so its data doesn't disappear | 1 | ~$0.50 |
| State storage bucket | A tiny storage bucket (S3) that stores Terraform's memory of what it built | 1 | ~$0.02 |
| Lock table | A tiny database table (DynamoDB) that stops me from accidentally running Terraform twice at once | 1 | ~$0.00 (free tier) |
| Domain name | None — I used a free trick (nip.io) instead of buying one | — | $0 |
| HTTPS certificate | Free, from Let's Encrypt | — | $0 |
| **Total** | | | **~$45–46/month** |

I'm not running a load balancer separately, since each server already has its
own public IP and Traefik (built into k3s) handles routing traffic to the
right part of the app.

## Compared to running everything on one single server

In an earlier version of this project, everything (website, backend, and
database) ran together on one single server, using Docker and Portainer to
manage it.

- That single-server setup cost roughly **$15/month** (just one small server).
- This new cluster setup costs roughly **$45/month** — about 3 times more.

**What the extra ~$30/month actually buys me:**
- If one server dies, the app keeps running on the other two (I tested this
  by disabling one server on purpose, and the app stayed online).
- The app can automatically create more copies of itself when it gets busy,
  and shrink back down when it's quiet, instead of one server struggling
  under heavy traffic.
- I can update the app with zero downtime (users never see an error during a
  deploy), instead of the whole site going offline for a few seconds during
  every update.
- If a piece of the app crashes, Kubernetes notices and restarts it
  automatically, instead of me having to notice and fix it myself.

**When is this NOT worth the extra cost?** For a small personal project, a
class assignment, or something with very few users, paying 3x more for this
kind of reliability doesn't make sense — the single $15/month server would be
perfectly fine. This setup starts to make sense once real people are
depending on the app being online and an outage would actually cost something
(lost sales, lost trust, etc.).

## How I'd cut this cost in half

The two worker servers and the control plane are the biggest cost by far. AWS
sells "spot" servers, which are the exact same servers but much cheaper
(sometimes 60-70% off), with the catch that AWS can take them back with very
little warning if they need the capacity elsewhere. I'd move my two worker
servers to spot pricing, since if AWS ever did reclaim one, Kubernetes would
just reschedule the app onto the other server automatically (the same
behavior I already tested when I manually drained a server). I'd keep the
control plane on a normal (non-spot) server since losing that one would be
more disruptive. That change alone would bring the worker server cost down by
more than half, cutting the whole project's monthly bill close to $30/month
instead of $45.

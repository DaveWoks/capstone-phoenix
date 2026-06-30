# Runbook

This is the exact set of steps to rebuild this project from nothing, plus the
day-to-day commands for working with it.

## Provision from zero

### 1. Infrastructure (Terraform)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set ssh_cidr to your current public IP (find it with: curl ifconfig.me)

terraform init
terraform apply
```

This creates the VPC, 3 subnets, the security group, and 3 EC2 servers
(1 control plane + 2 workers).

When it finishes, note the public/private IPs:

```bash
terraform output
```

### 2. Cluster (Ansible)

Update `infra/ansible/inventory/hosts.ini` with the public IPs from the
Terraform output above (`control`, `worker1`, `worker2`).

```bash
cd ../../
ssh-keyscan -H <control_ip> <worker1_ip> <worker2_ip> >> ~/.ssh/known_hosts

ansible all -i infra/ansible/inventory/hosts.ini -m ping
# confirm all 3 say "pong" before continuing

ansible-playbook infra/ansible/playbooks/k3s.yml \
  -i infra/ansible/inventory/hosts.ini
```

This installs k3s on the control plane, grabs the join token, and installs
k3s-agent on both workers using that token. Takes 5-10 minutes.

### 3. Get kubectl access

```bash
ansible k3s_master -i infra/ansible/inventory/hosts.ini \
  -m fetch -a "src=/etc/rancher/k3s/k3s.yaml dest=./kubeconfig flat=yes" -b

sed -i '' 's/127.0.0.1/<control_plane_public_ip>/' kubeconfig

export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

You should see all 3 nodes as `Ready`.

> **Note:** port `6443` is closed to the public internet by design (see
> ARCHITECTURE.md). If you need `kubectl` to work directly from your laptop
> during setup, temporarily add your IP to the security group:
> ```bash
> cd infra/terraform
> NEW_IP=$(curl -s ifconfig.me)
> terraform apply -auto-approve -var "ssh_cidr=${NEW_IP}/32"
> aws ec2 authorize-security-group-ingress \
>   --group-id <sg-id> --protocol tcp --port 6443 --cidr ${NEW_IP}/32
> ```
> Remove this rule again before submitting/sharing the project.

### 4. Platform tools (cert-manager + Argo CD)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml

kubectl rollout status deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager-webhook -n cert-manager
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager

kubectl apply -f manifests/config/clusterissuer.yaml

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd
```

Get the Argo CD admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

View the Argo CD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open `https://localhost:8080`, log in as `admin` with the password above.

### 5. Create the secret (out-of-band, never committed to git)

```bash
kubectl create namespace taskapp --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f manifests/config/secret.yaml
```

(`secret.yaml` is gitignored — see `.gitignore` — and `manifests/config/secret.yaml.example`
shows the shape without real values, if you need to recreate it from scratch.)

### 6. Hand the cluster over to GitOps

```bash
kubectl apply -f gitops/taskapp-application.yaml
kubectl get application -n argocd
```

Should show `Synced` and `Healthy`. From this point on, **do not** run
`kubectl apply` on anything inside `manifests/` by hand — push a commit to the
`develop` branch instead and let Argo CD pick it up.

### 7. Verify

```bash
curl -k https://taskapp.34.255.116.97.nip.io
kubectl get certificate -n taskapp
# should show READY: True
```

---

## Day-2 operations

### Scale a tier

Prefer a git commit so Argo CD stays the source of truth:

```bash
# edit manifests/frontend/deployment.yaml, change "replicas: 2" to "replicas: 3"
git add manifests/frontend/deployment.yaml
git commit -m "scale frontend to 3 replicas"
git push
```

Argo CD auto-syncs within ~3 minutes. To force it immediately:

```bash
kubectl patch application taskapp -n argocd \
  --type merge \
  -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}'
```

### Roll back a bad deploy

```bash
git revert <bad-commit-sha>
git push
```

Argo CD will sync the revert automatically. For an immediate manual rollback
without waiting on git:

```bash
kubectl rollout undo deployment/backend -n taskapp
```

### Run a new migration safely

The backend image's entrypoint already runs `alembic upgrade head` once per
pod on boot. Because Alembic tracks which migrations have already run, this is
safe even with multiple replicas: only the first pod to start actually applies
new migrations, the rest are no-ops. To trigger a new migration, just deploy a
new image version (bump the tag in `manifests/backend/deployment.yaml`,
commit, push).

### Seed/reset demo users

```bash
kubectl delete job seed-users -n taskapp --ignore-not-found
kubectl apply -f manifests/backend/seed-job.yaml
kubectl wait --for=condition=complete job/seed-users -n taskapp --timeout=60s
kubectl logs job/seed-users -n taskapp
```

### Rotate a secret

```bash
# edit manifests/config/secret.yaml (or wherever you keep the real values)
kubectl apply -f manifests/config/secret.yaml
kubectl rollout restart deployment/backend -n taskapp
kubectl rollout restart deployment/frontend -n taskapp
```

### My IP changed (mobile/home internet) and kubectl/ssh stopped working

```bash
cd infra/terraform
NEW_IP=$(curl -s ifconfig.me)
terraform apply -auto-approve -var "ssh_cidr=${NEW_IP}/32"
# if you also opened 6443 to your IP for kubectl access, update that rule too:
aws ec2 modify-security-group-rules \
  --region eu-west-1 \
  --group-id <sg-id> \
  --security-group-rules "SecurityGroupRuleId=<rule-id>,SecurityGroupRule={IpProtocol=tcp,FromPort=6443,ToPort=6443,CidrIpv4=${NEW_IP}/32,Description=temp admin access}"
```

---

## Failure recovery

### A worker node dies or is drained

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

What happens: all pods on that node (except DaemonSets) are evicted and
rescheduled onto the remaining healthy nodes. The app's `topologySpreadConstraints`
mean replicas are already spread out, so losing one node still leaves at least
one copy of frontend and backend running elsewhere. Tested live: draining
`ip-10-0-3-147` caused its pods to reschedule onto the other 2 nodes within
about 45 seconds, and `curl` checks against the public URL kept returning `200`
throughout (see `docs/EVIDENCE/failover.png`).

To bring the node back:

```bash
kubectl uncordon <node-name>
```

### A backend pod crashloops

```bash
kubectl get pods -n taskapp
kubectl describe pod <pod-name> -n taskapp
kubectl logs <pod-name> -n taskapp
kubectl logs <pod-name> -n taskapp --previous
```

`--previous` shows logs from before the last crash, which is usually where the
real error is. Common cause during this build: the database connection
environment variables (`DATABASE_HOST`, `DATABASE_USER`, etc.) not matching
what's actually in the `taskapp-secret` Secret — check
`kubectl describe pod <pod-name> -n taskapp` under "Environment Variables
from" to confirm the right Secret/ConfigMap is attached.

### A bad migration

```bash
# roll back the image to the previous known-good tag
kubectl set image deployment/backend backend=ghcr.io/ts-a-devops/taskapp-backend:<previous-tag> -n taskapp
```

If the migration already changed the schema in a way the old code can't read,
restore from a `pg_dump` backup (see `docs/COST.md` for backup status/limitations)
or manually run the down-migration:

```bash
kubectl exec -n taskapp deployment/backend -- alembic downgrade -1
```

### Postgres pod is rescheduled — proving the PVC re-attaches

```bash
kubectl delete pod postgres-0 -n taskapp
kubectl get pods -n taskapp -w
# wait for postgres-0 to show 1/1 Running again, then:
kubectl exec -n taskapp statefulset/postgres -- \
  psql -U taskuser -d taskmanager -c "SELECT id, username FROM users;"
```

If the same rows come back, the data survived. (Already proven and logged in
`docs/EVIDENCE/pvc-persist.log`.)

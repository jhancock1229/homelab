# homelab

Three Raspberry Pi 5s running k3s, managed with Ansible.

- **Machines** are configured by Ansible (`playbooks/base.yml`, then the k3s project's playbooks).
- **Apps** are deployed with plain Kubernetes manifests under `workloads/`.

Run everything from your Mac, in this folder.

## 0. One-time setup on the Mac

```sh
brew install ansible kubectl
ansible-galaxy collection install -r requirements.yml
openssl rand -hex 32 > .vault-pass && chmod 600 .vault-pass   # stays out of git
```

Check `inventory.yml`: the assumptions at the top, and set `k3s_version`.

```sh
cp group_vars/k3s_cluster/vault.yml.example group_vars/k3s_cluster/vault.yml
# edit vault.yml: set both values
ansible-vault encrypt group_vars/k3s_cluster/vault.yml
```

**Check:** `ansible k3s_cluster -m ping` returns `pong` from all three nodes.

## 1. Base layer

```sh
ansible-playbook playbooks/base.yml
# add --skip-tags tailscale if Tailscale is already installed and logged in
```

**Check:** `ansible k3s_cluster -a "tailscale ip -4"` prints an address for each node.

## 2. Cluster

```sh
ansible-playbook k3s.orchestration.site
```

The run ends by telling you where it wrote the kubeconfig on your Mac.

**Check:** `kubectl get nodes` shows three nodes, all `Ready`.

## 3. Test service

```sh
kubectl apply -f workloads/whoami/whoami.yaml
kubectl get pods -o wide        # three pods, spread across nodes
```

**Check:** from your phone on Tailscale, open `http://pi5-8a/whoami`.
Reload a few times; the hostname in the reply should change between pods.

## 4. Soak before trusting it

Over a week or two:

- [ ] Reboot each node in turn (`ansible pi5-8b -b -m reboot`), confirm it returns to `Ready`.
- [ ] Reboot the server node; confirm the test page comes back on its own.
- [ ] Pull the network cable on a worker for a minute; confirm pods reschedule or recover.
- [ ] `kubectl get events -A` shows nothing repeating.

## Upgrades

1. Change `k3s_version` in `inventory.yml`.
2. `ansible-playbook k3s.orchestration.upgrade`
3. `kubectl get nodes` shows the new version on all three.

With one server node the control plane is briefly unavailable during its
upgrade. Running workloads keep serving.

## Operating system updates

Security updates install automatically. Reboots do not. To apply everything
and reboot one node at a time when needed:

```sh
ansible-playbook playbooks/base.yml --skip-tags tailscale
```

## Rules

- Secrets live only in `vault.yml` (encrypted) and `.vault-pass` (ignored by git).
- Ansible manages machines. Kubernetes manifests manage apps. Do not deploy apps with Ansible.
- After the first successful install, pin `version` in `requirements.yml` to a commit.

## Apps

Seven apps live under `workloads/`. Deploy them after the cluster has passed its soak.

| App | Address | Purpose |
| --- | --- | --- |
| Home Assistant | `http://pi5-8b:8123` | Devices, automations, the Energy dashboard |
| Mosquitto | inside the cluster only: `mosquitto.home.svc:1883` | Message bus for sensors |
| Grafana (with Prometheus) | `http://<any node>:30030` | Cluster health and long-term charts |
| Uptime Kuma | `http://<any node>:30031` | Up/down checks and alerts |
| Speedtest Tracker | `http://<any node>:30032` | Internet speed every three hours |
| Homepage | `http://<any node>:30033` | Landing page linking the rest |
| Paperless-ngx | `http://pi5-8a:30034` | Bills and scanned documents |

All addresses work from your phone over Tailscale.

### 1. Create the secrets (once; these never go in git)

```sh
kubectl apply -f workloads/namespaces.yaml

kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 18)"

kubectl -n monitoring create secret generic speedtest-tracker \
  --from-literal=app-key="base64:$(openssl rand -base64 32)"

kubectl -n apps create secret generic paperless \
  --from-literal=secret-key="$(openssl rand -hex 32)" \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 18)"
```

To read a generated password back:

```sh
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

### 2. Deploy

```sh
kubectl apply -k workloads/
kubectl get pods -A --watch     # wait until everything is Running
```

**Check:** open Homepage on your phone and follow each link.

### 3. Notes

- **Storage** uses the `local-path` class that ships with k3s. Each app's data
  lives on the NVMe of the node it first started on, and the app stays on that
  node. Nothing here is backed up yet.
- **Home Assistant** is pinned to pi5-8b and uses that node's network directly.
  Plug USB radios into pi5-8b.
- **Mosquitto** accepts anonymous connections and is not reachable from outside
  the cluster. Add a password and expose it before pointing LAN sensors at it.
- **Image versions** track `stable` or `latest`. Pin them once things work, so
  an upgrade is a commit and not a surprise.
- **Updating one app:** edit its manifest, commit, `kubectl apply -k workloads/`.

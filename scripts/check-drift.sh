#!/bin/bash
set -euo pipefail

# ============================================================
# K3s Cluster Drift Detection
# Compares live cluster state against manifests/ repository.
#
# Categories reported:
#   MISSING   - Defined in repo but absent from cluster
#   DRIFTED   - Defined in repo AND cluster, but contents differ
#   UNTRACKED - Present in cluster but not tracked in repo
#
# Usage: ./scripts/check-drift.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
MANIFESTS_DIR="$REPO_ROOT/manifests"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}     K3s Cluster Drift Detection${NC}"
echo -e "${BLUE}========================================${NC}"

# Validate environment
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found in PATH${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to cluster${NC}"
echo ""

python3 - "$MANIFESTS_DIR" <<'PYEOF'
import json
import os
import subprocess
import sys
from pathlib import Path

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def run(cmd, silent=True):
    """Run a shell command and return stdout, or None on failure."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        if not silent:
            sys.stderr.write(f"WARN: {cmd}\n{result.stderr.strip()}\n")
        return None
    return result.stdout


def parse_multi_json(text):
    """
    Parse kubectl -o json output that may contain a single object,
    a List, or multiple concatenated JSON objects.
    """
    text = text.strip()
    if not text:
        return []

    # Single JSON object or List
    try:
        data = json.loads(text)
        if isinstance(data, dict) and data.get("kind") == "List":
            return [item for item in data.get("items", []) if isinstance(item, dict)]
        return [data] if isinstance(data, dict) else []
    except json.JSONDecodeError:
        pass

    # Multiple concatenated JSON objects
    decoder = json.JSONDecoder()
    objs, idx = [], 0
    while idx < len(text):
        try:
            obj, end = decoder.raw_decode(text, idx)
            objs.append(obj)
            idx = end
            while idx < len(text) and text[idx] in " \t\n\r,":
                idx += 1
        except json.JSONDecodeError:
            break

    items = []
    for obj in objs:
        if isinstance(obj, dict) and obj.get("kind") == "List":
            items.extend(obj.get("items", []))
        elif isinstance(obj, dict):
            items.append(obj)
    return items


def normalize(obj):
    """
    Strip server-managed and auto-assigned fields so that a
    manifest can be compared with its live counterpart.
    """
    obj = json.loads(json.dumps(obj))

    # --- status ---------------------------------------------------
    obj.pop("status", None)

    # --- metadata -------------------------------------------------
    meta = obj.get("metadata", {})
    for key in (
        "uid", "resourceVersion", "generation", "creationTimestamp",
        "deletionTimestamp", "deletionGracePeriodSeconds", "selfLink",
        "clusterName", "managedFields",
    ):
        meta.pop(key, None)

    # Annotations
    annotations = meta.get("annotations", {})
    annotations.pop("kubectl.kubernetes.io/last-applied-configuration", None)

    # deployment revision is added by the controller
    annotations.pop("deployment.kubernetes.io/revision", None)

    if not annotations:
        meta.pop("annotations", None)

    # Finalizers are often injected by controllers/admission webhooks
    meta.pop("finalizers", None)

    # Owner references (e.g. ReplicaSet owned by Deployment)
    meta.pop("ownerReferences", None)

    # --- kind-specific normalisations -----------------------------
    kind = obj.get("kind", "")
    spec = obj.get("spec", {})

    if kind == "Service":
        # clusterIP / clusterIPs are assigned by the apiserver
        spec.pop("clusterIP", None)
        spec.pop("clusterIPs", None)
        # internalTrafficPolicy default added by server
        spec.pop("internalTrafficPolicy", None)
        # ipFamilyPolicy default added by server
        spec.pop("ipFamilyPolicy", None)
        # sessionAffinity default
        spec.pop("sessionAffinity", None)

    elif kind == "PersistentVolumeClaim":
        # volumeName is bound by the control plane
        spec.pop("volumeName", None)
        # storage class might be defaulted; keep it if present

    elif kind == "Deployment":
        # Replicas may be defaulted; keep it.
        # Strategy may be defaulted; keep it.
        pass

    elif kind == "Job":
        # selector and manualSelector are generated for Jobs
        spec.pop("selector", None)
        spec.pop("manualSelector", None)

    elif kind == "Ingress":
        # ingressClassName may be defaulted
        pass

    return obj


# ------------------------------------------------------------------
# Phase 1 – Index repository manifests
# ------------------------------------------------------------------

def index_repo(manifests_dir):
    """Return (repo_index, file_map) dictionaries."""
    repo_index = {}
    file_map = {}

    yaml_files = list(Path(manifests_dir).rglob("*.yaml")) + list(Path(manifests_dir).rglob("*.yml"))

    for filepath in yaml_files:
        fname = filepath.name.lower()
        # Skip obvious template / secret files
        if "secret" in fname or "template" in fname:
            continue

        out = run(f'kubectl apply --dry-run=client -f "{filepath}" -o json')
        if not out:
            continue

        items = parse_multi_json(out)
        for item in items:
            kind = item.get("kind", "")
            if kind in ("Secret", "Event", "List") or not kind:
                continue

            ns = item.get("metadata", {}).get("namespace", "")
            name = item.get("metadata", {}).get("name", "")
            if not name:
                continue

            key = (kind, ns, name)
            repo_index[key] = normalize(item)
            file_map[key] = str(filepath.relative_to(manifests_dir.parent))

    return repo_index, file_map


# ------------------------------------------------------------------
# Phase 2 – Index live cluster
# ------------------------------------------------------------------

def discover_resource_types():
    """Return list of (scope, api_name) tuples, e.g. ('ns','deployments.apps')."""
    types = []

    ns_out = run("kubectl api-resources --namespaced=true --verbs=list -o name")
    if ns_out:
        for line in ns_out.strip().splitlines():
            t = line.strip()
            if t:
                types.append(("ns", t))

    cl_out = run("kubectl api-resources --namespaced=false --verbs=list -o name")
    if cl_out:
        for line in cl_out.strip().splitlines():
            t = line.strip()
            if t:
                types.append(("cluster", t))

    return types


def fetch_live(scope, api_name):
    """Fetch all objects of a given resource type; return list of dicts."""
    if scope == "ns":
        out = run(f"kubectl get {api_name} --all-namespaces -o json")
    else:
        out = run(f"kubectl get {api_name} -o json")

    if not out:
        return []

    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []

    return data.get("items", [])


def index_cluster():
    """Return dict of live resources indexed by (kind, namespace, name)."""
    cluster_index = {}
    resource_types = discover_resource_types()

    # Blacklist: infrastructure types never managed declaratively
    blacklist = {
        "secrets",
        "events",
        "events.events.k8s.io",
        "nodes",
        "bindings",
        "componentstatuses",
        "leases.coordination.k8s.io",
        "endpoints",
        "endpointslices.discovery.k8s.io",
        "flowschemas.flowcontrol.apiserver.k8s.io",
        "prioritylevelconfigurations.flowcontrol.apiserver.k8s.io",
        "runtimeclasses.node.k8s.io",
        "csidrivers.storage.k8s.io",
        "csinodes.storage.k8s.io",
        "csistoragecapacities.storage.k8s.io",
        "volumeattachments.storage.k8s.io",
        "apiservices.apiregistration.k8s.io",
        "mutatingwebhookconfigurations.admissionregistration.k8s.io",
        "validatingwebhookconfigurations.admissionregistration.k8s.io",
        "certificatesigningrequests.certificates.k8s.io",
        "tokenreviews.authentication.k8s.io",
        "localsubjectaccessreviews.authorization.k8s.io",
        "selfsubjectaccessreviews.authorization.k8s.io",
        "selfsubjectrulesreviews.authorization.k8s.io",
        "subjectaccessreviews.authorization.k8s.io",
        "podtemplates",
        "controllerrevisions.apps",
        "replicationcontrollers",
        # Additional infrastructure types
        "customresourcedefinitions.apiextensions.k8s.io",
        "customresourcedefinitions",
        "helmcharts.helm.cattle.io",
        "helmcharts",
        "addons.k3s.cattle.io",
        "addons",
        "ipaddresses.k8s.io",
        "ipaddresses",
        "servicecidrs.k8s.io",
        "servicecidrs",
        "nodemetrics.metrics.k8s.io",
        "nodemetrics",
        "podmetrics.metrics.k8s.io",
        "podmetrics",
        "certificaterequests.cert-manager.io",
        "certificaterequests",
        "orders.acme.cert-manager.io",
        "orders",
        "challenges.acme.cert-manager.io",
        "challenges",
        "replicasets.apps",
        "replicasets",
        "ingressclasses.networking.k8s.io",
        "ingressclasses",
        "gatewayclasses.gateway.networking.k8s.io",
        "gatewayclasses",
        "gateways.gateway.networking.k8s.io",
        "gateways",
        "grpcroutes.gateway.networking.k8s.io",
        "grpcroutes",
        "httproutes.gateway.networking.k8s.io",
        "httproutes",
        "referencegrants.gateway.networking.k8s.io",
        "referencegrants",
        "backendtlspolicies.gateway.networking.k8s.io",
        "backendtlspolicies",
        "etcdsnapshotfiles.k3s.cattle.io",
        "helmchartconfigs.helm.cattle.io",
        "helmchartconfigs",
    }

    # Known k3s system components to skip (allow custom ones through)
    kube_system_whitelist_noise = {
        "coredns",
        "local-path-provisioner",
        "metrics-server",
        "traefik",
        "svclb-traefik",
        "addon",
        "helm-install",
        "chart-content",
        "cluster-dns",
        "extension-apiserver-authentication",
        "kube-apiserver-legacy-service-account-token-tracking",
        "local-path-config",
        "cert-manager",
        "cert-manager-cainjector",
        "cert-manager-webhook",
    }

    for scope, api_name in resource_types:
        if api_name in blacklist:
            continue

        items = fetch_live(scope, api_name)
        for item in items:
            kind = item.get("kind", "")
            if kind in ("Secret", "Event", "List") or not kind:
                continue

            meta = item.get("metadata", {})
            ns = meta.get("namespace", "")
            name = meta.get("name", "")
            if not name:
                continue

            # Skip resources owned by a controller (children)
            owner_refs = meta.get("ownerReferences", [])
            if any(ref.get("controller", False) for ref in owner_refs):
                continue

            # Skip auto-generated per-namespace resources
            if kind == "ConfigMap" and name == "kube-root-ca.crt":
                continue
            if kind == "ServiceAccount" and name == "default":
                continue

            # Skip by name patterns
            if name.startswith("system:") or name.startswith("helm-"):
                continue
            if kind == "ConfigMap" and name.startswith("chart-content-"):
                continue

            # Skip openclaw resources entirely
            if "openclaw" in name.lower():
                continue

            # Smart kube-system filtering: skip known noise, keep unknown/custom
            if ns == "kube-system":
                is_known_noise = any(
                    name.startswith(prefix) or prefix in name
                    for prefix in kube_system_whitelist_noise
                )
                if is_known_noise:
                    continue

            # Skip system-generated platform RBAC (cluster-scoped)
            if ns == "" and kind in ("ClusterRole", "ClusterRoleBinding"):
                # Keep custom ones, skip built-in system roles
                if name.startswith("system:") or name in (
                    "admin", "edit", "view", "cluster-admin",
                    "traefik-kube-system", "k3s-cloud-controller-manager",
                    "local-path-provisioner-role", "clustercidrs-node",
                ):
                    continue

            # Skip PriorityClasses (platform-level)
            if kind == "PriorityClass":
                continue

            key = (kind, ns, name)
            cluster_index[key] = normalize(item)

    return cluster_index


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

def main():
    manifests_dir = sys.argv[1]
    if not os.path.isdir(manifests_dir):
        print(f"ERROR: Manifests directory not found: {manifests_dir}")
        sys.exit(1)

    print("Phase 1: Indexing repository manifests…")
    repo_index, file_map = index_repo(manifests_dir)
    print(f"  Tracked resources (excl. Secrets): {len(repo_index)}")

    print("\nPhase 2: Scanning live cluster…")
    cluster_index = index_cluster()
    print(f"  Live resources (excl. platform internals): {len(cluster_index)}")

    # ---- comparisons ----
    missing   = [k for k in repo_index if k not in cluster_index]
    untracked = [k for k in cluster_index if k not in repo_index]
    drifted   = []

    for key in repo_index:
        if key in cluster_index:
            repo_json    = json.dumps(repo_index[key], sort_keys=True)
            cluster_json = json.dumps(cluster_index[key], sort_keys=True)
            if repo_json != cluster_json:
                drifted.append(key)

    # ---- reporting ----
    exit_code = 0
    sep = "=" * 70

    def fmt_key(k):
        kind, ns, name = k
        ns_display = f"namespace={ns}" if ns else "cluster-scoped"
        return f"[{kind}] {name}  ({ns_display})"

    if missing:
        print(f"\n{sep}")
        print(f"MISSING   — {len(missing)} resources in repo but NOT in cluster")
        print(sep)
        for k in sorted(missing):
            print(f"  {fmt_key(k)}")
            fp = file_map.get(k, "unknown")
            print(f"            Manifest: manifests/{fp}")
        exit_code = 1

    if drifted:
        print(f"\n{sep}")
        print(f"DRIFTED   — {len(drifted)} resources differ between repo and cluster")
        print(sep)
        for k in sorted(drifted):
            print(f"  {fmt_key(k)}")
            fp = file_map.get(k, "unknown")
            print(f"            Manifest: manifests/{fp}")
        exit_code = 1

    if untracked:
        print(f"\n{sep}")
        print(f"UNTRACKED — {len(untracked)} resources in cluster but NOT in repo")
        print(sep)
        for k in sorted(untracked):
            print(f"  {fmt_key(k)}")
        exit_code = 1

    # Summary
    print(f"\n{sep}")
    if exit_code == 0:
        print("STATUS: CLUSTER IS FULLY IN SYNC WITH REPOSITORY")
    else:
        print(
            f"STATUS: OUT OF SYNC  (Missing: {len(missing)}, "
            f"Drifted: {len(drifted)}, Untracked: {len(untracked)})"
        )
    print(sep)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
PYEOF

#!/usr/bin/env python3
"""Compare docs/index.html with the live lab.

Checks every *.atlas.local name on the page against Pi-hole; the lab address
map (static addresses via DNS, MetalLB addresses via the cluster's LoadBalancer
services); and the VLAN subnets, DHCP ranges and custom firewall rules against
UniFi. Things the page plans but that don't exist yet are reported as PLANNED,
not as errors; things still live that the page has retired show as RETIRING.

Reads UniFi credentials from ~/.unifi-credentials (UNIFI_URL, UNIFI_USER,
UNIFI_PASSWORD). Needs `dig`, `kubectl` (context admin@atlas) and network
access to the lab.
"""
import http.cookiejar, json, pathlib, re, ssl, subprocess, sys, urllib.request

PAGE = pathlib.Path(__file__).resolve().parent.parent / "docs" / "index.html"
PIHOLE = "192.168.0.101"

# What the page's address plan and firewall table say. Keep in sync with the page.
NETWORKS = {
    "Default":   ("192.168.0.1/24",  "192.168.0.10",   "192.168.0.99"),   # becomes Management
    "Home":      ("192.168.30.1/24", "192.168.30.10",  "192.168.30.254"), # new in the redesign
    "IoT":       ("192.168.10.1/24", "192.168.10.100", "192.168.10.254"),
    "Atlas Lab": ("192.168.20.1/24", "192.168.20.100", "192.168.20.254"),
}
FIREWALL_RULES = {"Allow Austin MAC to LAB", "Allow Austin MAC to Management",
                  "Allow Home to IoT", "Allow DNS to PiHole", "Restrict gateway admin"}
# Live today, replaced by the redesign.
FIREWALL_RETIRING = {"Allow LAB DNS to PiHole", "Allow LAB to Proxmox API", "Allow IoT DNS to PiHole"}
PLANNED_NETWORKS = {"Home"}
PLANNED = {"aap.atlas.local", "talos-worker-02.atlas.local"}

# The page's lab address map. Keep in sync with the page.
STATIC = {
    "192.168.20.5": "proxmox.atlas.local",
    "192.168.20.3": "atlas-pihole.atlas.local",
    "192.168.20.10": "talos-cp.atlas.local",
    "192.168.20.11": "talos-worker-01.atlas.local",
    "192.168.20.12": "aap.atlas.local",
    "192.168.20.13": "talos-worker-02.atlas.local",
    "192.168.20.14": "llm.atlas.local",
    "192.168.20.15": "vault.atlas.local",
}
METALLB = {
    "192.168.20.50": "argocd/argocd-server",
    "192.168.20.52": "vcsim/vcenter-01",
    "192.168.20.53": "vcsim/vcenter-02",
}
# Addresses that change in the redesign: name -> address it has today.
MOVES = {"proxmox.atlas.local": "192.168.0.100", "atlas-pihole.atlas.local": "192.168.0.101"}
# Still live today, but gone in the target design shown on the page.
RETIRING = {}  # e.g. {"192.168.20.51": "namespace/service"}

problems = 0
def report(status, what, detail=""):
    global problems
    if status == "MISMATCH":
        problems += 1
    print(f"{status:<9} {what}{'  ' + detail if detail else ''}")

def dns_names(html):
    names = set(re.findall(r"\b[a-z][a-z0-9-]*\.atlas\.local\b", html))
    if "vcenter-01…04.atlas.local" in html:
        names |= {f"vcenter-0{i}.atlas.local" for i in range(1, 5)}
    return sorted(names)

def dig(name):
    return subprocess.run(["dig", "+short", f"@{PIHOLE}", name],
                          capture_output=True, text=True).stdout.split()

def check_static():
    for ip, name in STATIC.items():
        found = dig(name)
        if ip in found:
            report("OK", f"{ip} static", name)
        elif not found and name in PLANNED:
            report("PLANNED", f"{ip} static", f"{name} not in Pi-hole yet")
        elif MOVES.get(name) in found:
            report("PLANNED", f"{ip} static", f"{name} still at {MOVES[name]}; moves with the M920q")
        else:
            report("MISMATCH", f"{ip} static", f"{name} resolves to {found or 'nothing'}")

def check_metallb():
    out = subprocess.run(["kubectl", "--context", "admin@atlas", "get", "svc", "-A", "-o", "json"],
                         capture_output=True, text=True, timeout=30)
    if out.returncode:
        report("MISMATCH", "MetalLB", "couldn't reach the cluster with kubectl"); return
    live = {}
    for svc in json.loads(out.stdout)["items"]:
        for ing in svc.get("status", {}).get("loadBalancer", {}).get("ingress", []) or []:
            if ing.get("ip"):
                live[ing["ip"]] = f'{svc["metadata"]["namespace"]}/{svc["metadata"]["name"]}'
    for ip in sorted(set(METALLB) | set(live), key=lambda a: int(a.split(".")[-1])):
        if METALLB.get(ip) == live.get(ip):
            report("OK", f"{ip} MetalLB", live[ip])
        elif ip not in live:
            report("MISMATCH", f"{ip} MetalLB", f"page says {METALLB[ip]}, no service holds it")
        elif ip not in METALLB and RETIRING.get(ip) == live[ip]:
            report("RETIRING", f"{ip} MetalLB", f"{live[ip]} until it is retired")
        elif ip not in METALLB:
            report("MISMATCH", f"{ip} MetalLB", f"{live[ip]} holds it but the page shows it free")
        else:
            report("MISMATCH", f"{ip} MetalLB", f"page says {METALLB[ip]}, live is {live[ip]}")

def check_dns(html):
    for name in dns_names(html):
        ip = subprocess.run(["dig", "+short", f"@{PIHOLE}", name],
                            capture_output=True, text=True).stdout.strip()
        if ip:
            report("OK", name, ip.splitlines()[0])
        elif name in PLANNED:
            report("PLANNED", name, "not in Pi-hole yet")
        else:
            report("MISMATCH", name, "on the page but not in Pi-hole")

def unifi():
    creds = {}
    for line in (pathlib.Path.home() / ".unifi-credentials").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            creds[k.strip().removeprefix("export ").strip()] = v.strip().strip("'\"")
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                         urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    base = creds["UNIFI_URL"].rstrip("/")
    login = json.dumps({"username": creds["UNIFI_USER"], "password": creds["UNIFI_PASSWORD"]}).encode()
    resp = opener.open(urllib.request.Request(f"{base}/api/auth/login", data=login,
                                              headers={"Content-Type": "application/json"}), timeout=10)
    csrf = resp.headers.get("x-csrf-token", "")
    def get(path):
        req = urllib.request.Request(f"{base}/proxy/network{path}", headers={"x-csrf-token": csrf})
        return json.load(opener.open(req, timeout=10))
    return get

def check_unifi():
    get = unifi()
    nets = {n["name"]: n for n in get("/api/s/default/rest/networkconf")["data"]}
    for name, (subnet, start, stop) in NETWORKS.items():
        n = nets.get(name)
        if not n:
            if name in PLANNED_NETWORKS:
                report("PLANNED", f"network {name}", "not created in UniFi yet")
            else:
                report("MISMATCH", f"network {name}", "missing in UniFi")
            continue
        live = (n.get("ip_subnet"), n.get("dhcpd_start"), n.get("dhcpd_stop"))
        if live == (subnet, start, stop):
            report("OK", f"network {name}", f"{subnet}, DHCP {start}-{stop}")
        else:
            report("MISMATCH", f"network {name}", f"page {subnet} {start}-{stop}, live {live[0]} {live[1]}-{live[2]}")
    live_rules = {p["name"] for p in get("/v2/api/site/default/firewall-policies") if not p.get("predefined")}
    for rule in sorted(FIREWALL_RULES | live_rules):
        if rule in FIREWALL_RULES and rule in live_rules:
            report("OK", f"firewall: {rule}")
        elif rule in FIREWALL_RULES:
            report("PLANNED", f"firewall: {rule}", "not in UniFi yet")
        elif rule in FIREWALL_RETIRING:
            report("RETIRING", f"firewall: {rule}", "replaced by the redesign")
        else:
            report("MISMATCH", f"firewall: {rule}", "in UniFi but not on the page")

if __name__ == "__main__":
    html = PAGE.read_text()
    print(f"Checking {PAGE.name} against the live lab\n")
    check_dns(html)
    check_static()
    check_metallb()
    check_unifi()
    print(f"\n{problems} mismatch(es)")
    sys.exit(1 if problems else 0)

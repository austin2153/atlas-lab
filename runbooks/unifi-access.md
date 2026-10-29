# UniFi Controller Access

This document describes how Claude connects to the UniFi Network controller for reviewing and managing the home lab network setup.

## Credentials File

Credentials are stored locally at `~/.unifi-credentials` (not committed to git). Create the file with the following format:

```
UNIFI_URL=https://<controller-ip>
UNIFI_USER=<local-admin-username>
UNIFI_PASSWORD=<password>
```

Restrict permissions so only your user can read it:

```bash
chmod 600 ~/.unifi-credentials
```

## Connecting

Claude reads credentials from `~/.unifi-credentials` and interacts with the UniFi controller via its local REST API. A local-only admin account is used so authentication does not require internet connectivity or Ubiquiti cloud 2FA.

### Example — get auth cookie

```bash
source ~/.unifi-credentials
curl -sk -c /tmp/unifi-cookie.txt -X POST "$UNIFI_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASSWORD\"}"
```

### Example — list sites

```bash
curl -sk -b /tmp/unifi-cookie.txt "$UNIFI_URL/proxy/network/api/self/sites"
```

## Notes

- The controller is a **Home Cloud Gateway Ultra** on the local network
- A local-only admin account is used (no Ubiquiti cloud account required) — credentials are in `~/.unifi-credentials`
- The cookie file `/tmp/unifi-cookie.txt` is ephemeral and cleared on reboot
- Always source credentials from `~/.unifi-credentials` — never hardcode or echo passwords in the terminal

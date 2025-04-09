# Hysteria 2 Server Setup Script - Usage Guide

## Prerequisites

* An Ubuntu or Debian-based Linux server.
* Root access or a user account with `sudo` privileges.
* The following commands installed: `bash`, `curl`, `sudo`, `openssl`, `id`, `systemctl`.
* Internet connectivity to download the Hysteria installation script and fetch the public IP address.

## Usage

The script is designed to be run directly from a URL using `bash` and `curl`.

**Security Note:** Running scripts directly from the internet carries inherent risks. Ensure you trust the source of the script, official hysteria2 script from website (`get.hy2.sh` and the script itself) before executing.

The script will validate `sudo` privileges early and prompt for a password if necessary. Upon successful completion, it will output a Hysteria 2 connection string.

---

# Commands Examples:

## 1️⃣ Example: Default Settings

This command runs the script using the default port `443` and the default masquerade domain `bing.com`

*Command:*

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/coder-dao/hysteria2/refs/heads/main/install.sh)
```

*Result:*

```md
--------------------------------------------------
Hysteria Connection String:
hysteria2://GENERATED_PASSWORD@SERVER_IPV4:443/?sni=bing.com&alpn=h3&insecure=1#Hysteria
--------------------------------------------------
```

---

## 2️⃣ Example: Custom Port Only

This command runs the script using a custom port `3333` and the default masquerade domain `bing.com`

*Command:*

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/coder-dao/hysteria2/refs/heads/main/install.sh) --port 3333
```

*Result:*
```markdown
--------------------------------------------------
Hysteria Connection String:
hysteria2://GENERATED_PASSWORD@SERVER_IPV4:3333/?sni=bing.com&alpn=h3&insecure=1#Hysteria
--------------------------------------------------
```

---

## 3️⃣ Example: Custom Port and Masquerade Domain

This command runs the script using a custom port `3333` and a custom masquerade domain `example.com`

*Command:*

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/coder-dao/hysteria2/refs/heads/main/install.sh) --port 3333 --domain my.custom.domain.com
```

*Result:*
```markdown
--------------------------------------------------
Hysteria Connection String:
hysteria2://GENERATED_PASSWORD@SERVER_IPV4:3333/?sni=my.custom.domain.com&alpn=h3&insecure=1#Hysteria
--------------------------------------------------
```
---

## Arguments:

`--port` <number>: Sets the listening port for Hysteria (e.g., 3333). Must be between 1 and 65535.

`--domain` <domain_name>: Sets the domain used for the masquerade URL.

*(Note: GENERATED_PASSWORD and SERVER_IPV4 in the result formats above

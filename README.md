# Starfall Installer

Onbeheerde installatie van **Starfall Exodus** op **Docker**.

Dit script downloadt automatisch de laatste versie van Starfall vanuit GitHub,
installeert Docker (indien nodig), start de volledige stack (MariaDB, Redis,
web, websocket en scheduler) en maakt een adminaccount aan.

> **Let op:** De Starfall-repository (`rorymeijer/starfall`) is privé. Dit
> bootstrapscript staat daarom in deze publieke repo. Tijdens de installatie
> wordt gevraagd om een GitHub-gebruikersnaam en een Personal Access Token
> (PAT) met leesrechten op de repository, zodat de bron gedownload kan worden.

---

# Vereisten

* Linux-server (Debian, Ubuntu of vergelijkbaar)
* Internetverbinding
* Een GitHub Personal Access Token met minimaal **Contents: Read** rechten op `rorymeijer/starfall`

> Docker en Docker Compose worden automatisch geïnstalleerd wanneer ze nog
> ontbreken. Een externe database is **niet** nodig: de stack levert MariaDB en
> Redis zelf mee.

---

# Installeren

Voer op de Docker-host uit:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/rorymeijer/starfall-install/main/docker-unattended-install.sh)"
```

Tijdens de installatie wordt gevraagd om:

* GitHub gebruikersnaam
* GitHub Personal Access Token

De rest verloopt volledig automatisch.

---

# Wat installeert het script?

Het script:

* vraagt om GitHub-gegevens voor de privé-bronrepository;
* installeert Docker (indien nodig);
* downloadt Starfall vanuit GitHub naar `/srv/docker/starfall`;
* kiest automatisch een vrije host-poort (vanaf 8080);
* draagt de installatie over aan `backend/install.sh` (genereert een `.env` met
  sterke geheimen, start de stack, migreert en maakt een adminaccount aan);
* stelt een nachtelijke back-up-cronjob op de host in (03:30);
* toont de URL's en het admin-wachtwoord.

---

# Onbeheerd draaien

Volledig onbeheerd (zonder prompts) kan via omgevingsvariabelen:

| Variabele              | Betekenis                        | Standaard              |
| ---------------------- | -------------------------------- | ---------------------- |
| `GITHUB_USER`          | GitHub-gebruiker (privérepo)     | –                      |
| `GITHUB_TOKEN`         | GitHub-token (PAT)               | –                      |
| `STARFALL_REPO`        | GitHub owner/repo                | `rorymeijer/starfall`  |
| `STARFALL_BRANCH`      | branch                           | `main`                 |
| `STARFALL_DIR`         | installatiemap                   | `/srv/docker/starfall` |
| `STARFALL_PORT`        | begin-host-poort                 | `8080`                 |
| `STARFALL_DOMAIN`      | publieke hostnaam                | –                      |
| `STARFALL_ADMIN_USER`  | adminnaam                        | `admin`                |
| `STARFALL_ADMIN_EMAIL` | admin-e-mail                     | `admin@<domein>`       |
| `STARFALL_ADMIN_PASS`  | adminwachtwoord                  | willekeurig            |
| `STARFALL_NO_CRON=1`   | sla de back-up-cron over         | –                      |

Voorbeeld:

```bash
GITHUB_USER=jouwnaam GITHUB_TOKEN=ghp_xxx STARFALL_DOMAIN=starfall.example.nl \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/rorymeijer/starfall-install/main/docker-unattended-install.sh)"
```

---

# GitHub Token

Maak een Personal Access Token aan via:

https://github.com/settings/personal-access-tokens

Minimale rechten:

* Repository access → **Only select repositories**
* Selecteer **starfall**
* Permissions:

  * **Contents → Read-only**

---

# Na de installatie

Het script toont na afloop de URL's en het admin-wachtwoord. Beheer:

```bash
cd /srv/docker/starfall/backend && docker compose ps
```

Updaten:

```bash
cd /srv/docker/starfall/backend && ./update.sh
```

> **Productie?** Zet `STARFALL_DOMAIN` en plaats een TLS-reverse-proxy vóór de
> gekozen host-poort (zie `backend/docs/DEPLOYMENT.md` in de hoofdrepository).

---

# Hoofdrepository

https://github.com/rorymeijer/starfall

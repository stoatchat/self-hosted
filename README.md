<div align="center">
<h1>
  Stoat Self-Hosted
  
  [![Stars](https://img.shields.io/github/stars/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/stargazers)
  [![Forks](https://img.shields.io/github/forks/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/network/members)
  [![Pull Requests](https://img.shields.io/github/issues-pr/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/pulls)
  [![Issues](https://img.shields.io/github/issues/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/issues)
  [![Contributors](https://img.shields.io/github/contributors/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/graphs/contributors)
  [![License](https://img.shields.io/github/license/revoltchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/revoltchat/self-hosted/blob/main/LICENSE)
</h1>
Self-hosting Stoat using Docker
</div>
<br/>

This repository contains configurations and instructions that can be used for deploying a full instance of Stoat, including the back-end, web front-end, file server, and metadata and image proxy.

> [!WARNING]
> If you are updating an instance from before November 28, 2024, please consult the [notices section](#notices) at the bottom.

> [!IMPORTANT]
> A list of security advisories is [provided at the bottom](#security-advisories).

> [!NOTE]
> Please consult _[What can I do with Stoat, and how do I self-host?](https://developers.revolt.chat/faq.html#admonition-what-can-i-do-with-revolt-and-how-do-i-self-host)_ on our developer site for information about licensing and brand use.

> [!NOTE]
> amd64 builds are not currently available for the web client.

> [!NOTE]
> This guide does not include working voice channels ([#138](https://github.com/revoltchat/self-hosted/pull/138#issuecomment-2762682655)). A [rework](https://github.com/revoltchat/backend/issues/313) is currently in progress.

## Table of Contents

- [Deployment](#deployment)
- [Updating](#updating)
- [Advanced Deployment](#advanced-deployment)
- [Additional Notes](#additional-notes)
  - [Custom Domain](#custom-domain)
  - [Placing Behind Another Reverse-Proxy or Another Port](#placing-behind-another-reverse-proxy-or-another-port)
  - [Insecurely Expose the Database](#insecurely-expose-the-database)
  - [Mongo Compatibility](#mongo-compatibility)
  - [Making Your Instance Invite-only](#making-your-instance-invite-only)
- [Notices](#notices)
- [Security Advisories](#security-advisories)

## Deployment

To get started, find yourself a suitable server to deploy onto, we recommend starting with at least 2 vCPUs and 2 GB of memory.

> [!TIP]
>
> **We've partnered with Hostinger to bring you a 20% discount off VPS hosting!**
>
> [![Deploy on Hostinger](https://assets.hostinger.com/vps/deploy.svg)](https://www.hostinger.com/vps/docker-hosting?compose_url=https://raw.githubusercontent.com/revoltchat/self-hosted/refs/heads/master/compose.yml&REFERRALCODE=REVOLTCHAT)
>
> We recommend using the _KVM 2_ plan at minimum!\
> Our testing environment for self-hosted currently sits on a KVM 2 instance, and we are happy to assist with issues.

The instructions going forward will use Hostinger as an example hosting platform, but you should be able to adapt these to other platforms as necessary. There are important details throughout.

![Select the location](.github/guide/hostinger-1.location.webp)

When asked, choose **Ubuntu Server** as your operating system; this is used by us in production, and we recommend its use.

![Select the operating system](.github/guide/hostinger-2.os.webp)

If you've chosen to go with Hostinger, they include integrated malware scanning, which may be of interest:

![Consider malware scanning](.github/guide/hostinger-3.malware.webp)

You should set a secure root password for login (_or disable password login after setup, which is explained later! but you shouldn't make the password trivial until after this is secured at least!_) and we recommend that you configure an SSH key:

![Configuration unfilled](.github/guide/hostinger-4.configuration.webp)
![Configuration filled](.github/guide/hostinger-5.configuration.webp)

Make sure to confirm everything is correct!

![Confirmation](.github/guide/hostinger-6.complete.webp)

Wait for your VPS to be created...

| ![Wait for creation](.github/guide/hostinger-7.wait.webp) | ![Wait for creation](.github/guide/hostinger-8.connect.webp) |
| --------------------------------------------------------- | ------------------------------------------------------------ |

After installation, SSH into the machine:

```bash
# use the provided IP address to connect:
ssh root@<ip address>
# .. if you have a SSH key configured
ssh root@<ip address> -i path/to/id_rsa
```

And now we can proceed with some basic configuration and securing the system:

```bash
# update the system
apt-get update && apt-get upgrade -y

# configure firewall
ufw allow ssh
ufw allow http
ufw allow https
ufw default deny
ufw enable

# if you have configured an SSH key, disable password authentication:
sudo sed -E -i 's|^#?(PasswordAuthentication)\s.*|\1 no|' /etc/ssh/sshd_config
if ! grep '^PasswordAuthentication\s' /etc/ssh/sshd_config; then echo 'PasswordAuthentication no' |sudo tee -a /etc/ssh/sshd_config; fi

# reboot to apply changes
reboot
```

Your system is now ready to proceed with installation, but before we continue, you should configure your domain.

![Cloudflare DNS configuration](.github/guide/cloudflare-dns.webp)

Your domain (or a subdomain) should point to the server's IP (A and AAAA records) or CNAME to the hostname provided.

Next, we must install the required dependencies:

```bash
# ensure Git and Docker are installed
apt-get update
apt-get install ca-certificates curl git micro
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Now, we can pull in the configuration for Stoat:

```bash
git clone https://github.com/revoltchat/self-hosted stoat
cd stoat
```

Generate a configuration file by running:

```bash
chmod +x ./generate_config.sh
./generate_config.sh your.domain
```

You can find [more options here](https://github.com/revoltchat/backend/blob/stable/crates/core/config/Revolt.toml), some noteworthy configuration options:

- Email verification
- Captcha
- A custom S3 server
- iOS & Android notifications (Requires Apple/Google developer accounts)

If you'd like to edit the configuration, just run:

```bash
micro Revolt.toml
```

Finally, we can start up Stoat. First, run it in the foreground with:

```bash
docker compose up
```

If it runs without any critical errors, you can stop it with <kbd>Ctrl</kbd> + <kbd>C</kbd> and run it detached (in the background) by appending `-d`.

```bash
docker compose up -d
```

## Updating

Before updating, ensure you consult the notices at the top of this README, **as well as** [the notices](#notices) at the bottom, to check if there are any important changes to be aware of.

Pull the latest version of this repository:

```bash
git pull
```

Check if your configuration file is correct by opening [the reference config file](https://github.com/revoltchat/backend/blob/df074260196f5ed246e6360d8e81ece84d8d9549/crates/core/config/Revolt.toml) and your `Revolt.toml` to compare changes.

Then pull all the latest images:

```bash
docker compose pull
```

Then restart the services:

```bash
docker compose up -d
```

## Advanced Deployment

This guide assumes you know your way around a Linux terminal and Docker.

Prerequisites before continuing:

- [Git](https://git-scm.com)
- [Docker](https://www.docker.com)

Clone this repository.

```bash
git clone https://github.com/revoltchat/self-hosted stoat
cd stoat
```

Create `.env.web` and download `Revolt.toml`, then modify them according to your requirements.

> [!WARNING]
> The default configurations are intended exclusively for testing and will only work locally. If you wish to deploy to a remote server, you **must** edit the URLs in `.env.web` and `Revolt.toml`. Please reference the section below on [configuring a custom domain](#custom-domain).

```bash
echo "HOSTNAME=http://local.stoat.chat" > .env.web
echo "REVOLT_PUBLIC_URL=http://local.stoat.chat/api" >> .env.web
wget -O Revolt.toml https://raw.githubusercontent.com/revoltchat/backend/main/crates/core/config/Revolt.toml
```

Then start Stoat:

```bash
docker compose up -d
```

## Additional Notes

### Custom Domain

To configure a custom domain, you can either generate a config for https by running:

```
chmod +x ./generate_config.sh
./generate_config.sh your.domain
```

Or alternatively do it manually, you will need to replace _all_ instances of `local.stoat.chat` in `Revolt.toml` and `.env.web` to your chosen domain (here represented as `example.com`), like so:

```diff
# .env.web
- REVOLT_PUBLIC_URL=http://local.stoat.chat/api
+ REVOLT_PUBLIC_URL=http://example.com/api
```

```diff
# Revolt.toml
- app = "http://local.stoat.chat"
+ app = "http://example.com"
```

In the case of `HOSTNAME`, you must strip the protocol prefix:

```diff
# .env.web
- HOSTNAME=http://example.com
+ HOSTNAME=example.com
```

You will likely also want to change the protocols to enable HTTPS:

```diff
# .env.web
- REVOLT_PUBLIC_URL=http://example.com/api
+ REVOLT_PUBLIC_URL=https://example.com/api
```

```diff
# Revolt.toml
- app = "http://example.com"
+ app = "https://example.com"

- events = "ws://example.com/ws"
+ events = "wss://example.com/ws"
```

### Placing Behind Another Reverse-Proxy or Another Port

If you'd like to place Stoat behind another reverse proxy or on a non-standard port, you'll need to edit `compose.yml`.

Override the port definitions on `caddy`:

```yml
# compose.yml
services:
  caddy:
    ports:
      - "1234:80"
```

> [!WARNING]
> This file is not included in `.gitignore`. It may be sufficient to use an override file, but that will not remove port `80` / `443` allocations.

Update the hostname used by the web server:

```diff
# .env.web
- HOSTNAME=http://example.com
+ HOSTNAME=:80
```

You can now reverse proxy to <http://localhost:1234>.

### Insecurely Expose the Database

You can insecurely expose the database by adding a port definition:

```yml
# compose.override.yml
services:
  database:
    ports:
      - "27017:27017"
```

For obvious reasons, be careful doing this.

### Mongo Compatibility

Older processors may not support the latest MongoDB version; you may pin to MongoDB 4.4 as such:

```yml
# compose.override.yml
services:
  database:
    image: mongo:4.4
```

### Making Your Instance Invite-only

Enable invite-only mode by setting `invite_only` in `Revolt.toml` to `true`.

Create an invite:

```bash
# drop into mongo shell
docker compose exec database mongosh

# create the invite
use revolt
db.invites.insertOne({ _id: "enter_an_invite_code_here" })
```

## Notices

> [!IMPORTANT]
> If you deployed Stoat before [2022-10-29](https://github.com/minio/docs/issues/624#issuecomment-1296608406), you may have to tag the `minio` image release if it's configured in "fs" mode.
>
> ```yml
> image: minio/minio:RELEASE.2022-10-24T18-35-07Z
> ```

> [!IMPORTANT]
> If you deployed Stoat before [2023-04-21](https://github.com/revoltchat/backend/commit/32542a822e3de0fc8cc7b29af46c54a9284ee2de), you may have to flush your Redis database.
>
> ```bash
> # for stock Redis and older KeyDB images:
> docker compose exec redis redis-cli
> # ...or for newer KeyDB images:
> docker compose exec redis keydb-cli
>
> # then run:
> FLUSHDB
> ```

> [!IMPORTANT]
> As of 30th September 2024, Autumn has undergone a major refactor, which requires a manual migration.
>
> To begin, add a temporary container that we can work from:
>
> ```yml
> # compose.override.yml
> services:
>   migration:
>     image: node:21
>     volumes:
>       - ./migrations:/cwd
>     command: "bash -c 'while true; do sleep 86400; done'"
> ```
>
> Then switch to the shell:
>
> ```bash
> docker compose up -d database migration
> docker compose exec migration bash
> ```
>
> Now we can run the migration:
>
> ```bash
> cd /cwd
> npm i mongodb
> node ./20240929-autumn-rewrite.mjs
> ```

> [!IMPORTANT]
> As of November 28, 2024, the following breaking changes have been applied:
>
> - Rename config section `api.vapid` -> `pushd.vapid`
> - Rename config section `api.fcm` -> `pushd.fcm`
> - Rename config section `api.apn` -> `pushd.apn`
>
> These will NOT automatically be applied to your config and must be changed/added manually.
>
> The following components have been added to the compose file:
>
> - Added `rabbit` (RabbitMQ) and `pushd` (Stoat push daemon)

## Security Advisories

- (`2024-06-21`) [GHSA-f26h-rqjq-qqjq revoltchat/backend: Unrestricted account creation.](https://github.com/revoltchat/backend/security/advisories/GHSA-f26h-rqjq-qqjq)
- (`2024-12-17`) [GHSA-7f9x-pm3g-j7p4 revoltchat/january: January service can call itself recursively, causing heavy load.](https://github.com/revoltchat/january/security/advisories/GHSA-7f9x-pm3g-j7p4)
- (`2025-02-10`) [GHSA-8684-rvfj-v3jq revoltchat/backend: Webhook tokens are freely accessible for users with read permissions.](https://github.com/revoltchat/backend/security/advisories/GHSA-8684-rvfj-v3jq)
- (`2025-02-10`) [GHSA-h7h6-7pxm-mc66 revoltchat/backend: Nearby message fetch requests can be crafted to fetch entire message history.](https://github.com/revoltchat/backend/security/advisories/GHSA-h7h6-7pxm-mc66)

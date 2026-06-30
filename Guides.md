<div align="center">
<h1>
  Stoat Self-Hosted
  
  [![Stars](https://img.shields.io/github/stars/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/stargazers)
  [![Forks](https://img.shields.io/github/forks/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/network/members)
  [![Pull Requests](https://img.shields.io/github/issues-pr/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/pulls)
  [![Issues](https://img.shields.io/github/issues/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/issues)
  [![Contributors](https://img.shields.io/github/contributors/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/graphs/contributors)
  [![License](https://img.shields.io/github/license/stoatchat/self-hosted?style=flat-square&logoColor=white)](https://github.com/stoatchat/self-hosted/blob/main/LICENSE)
</h1>
Self-hosting Stoat Guides
</div>
<br/>

Below are guides provided by the core team and by the community. Contributions to guides are welcome!

## Table of Contents

- [Placing Stoat Behind Other Reverse Proxies](#placing-stoat-behind-other-reverse-proxies)
  - [NGINX](#nginx)
- [Making Your Instance Invite-only](#making-your-instance-invite-only)
- [Enabling the Gif Picker](#enabling-the-gif-picker)

## Placing Stoat Behind Other Reverse Proxies

Stoat self host is configured to use a built-in Caddy proxy by default; however, it works with other reverse proxies as well. Below are guides on putting Stoat self host behind different reverse proxies. If there is a reverse proxy that you'd like to use that is not documented, feel free to open a PR for adding a guide for that reverse proxy here.

>[!WARNING]
> It is strongly recommended if you do not know how to manage a reverse proxy already that you leave Stoat to be hosted by the built-in Caddy proxy. These guides are supplemental, and will not cover every step or every use case.

>[!NOTE]
> If you plan on using a reverse proxy other than the built in proxy, you will need to enter `y` during the configuration process when it asks if you'd like to place Stoat behind another reverse proxy. This will expose the Caddy container on port 8880 by default and you can reverse proxy to <http://localhost:8880>. If you'd like to change what port the Caddy container listens on, you can change it in the `compose.overrides.yml` file.

Assumptions made by these guides:
- The domain name for your Stoat self host is `your.domain`
- Your Caddy is configured to run on port 8880

### NGINX

Configuring Stoat self host behind NGINX involves configuring the websocket routes. All other steps for configuring NGINX are the same as any other service. These instructions assume you are using an NGINX installed via apt on a Debian based server. Most of the instructions here should apply to a docker container install as well. Other configurations are left as an exercise for the reader.

#### Install NGINX and Certbot

```bash
sudo apt update && sudo apt install nginx certbot python3-certbot-nginx
```

#### Add a site file to sites-available

Create a configuration file somewhere for Stoat and open it, you can do it at `/etc/nginx/sites-available`.

```bash
sudo micro /etc/nginx/sites-available/your.domain
```

Configure your domain, below is a configuration that should work out of the box (after using certbot.) Ensure that websocket support is enabled for the `/ws` and `/livekit` routes.

```
server {
    server_name your.domain;

    listen 80;
    listen [::]80;

    location / {
        proxy_pass http://localhost:8880;
        proxy_set_header Host $server_name;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://localhost:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $server_name;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /livekit {
        allow all;
        proxy_pass http://localhost:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $server_name;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Enable the site

If you chose a different file name, make sure this reflects that.

```bash
sudo ln -s /etc/nginx/sites-available/your.domain /etc/nginx/sites-enabled/your.domain
```

#### Test the new configuration

```bash
sudo nginx -t
```

If there are any errors, address them.

#### Restart NGINX

```bash
sudo service nginx restart
```

#### Test that you can reach the service

Open `http://your.domain` in your browser. You should land on the login page. Don't login yet, as you need to enable SSL.

#### Run Certbot

Certbot configuration is not covered by this guide. Please view Certbot documentation for nginx. After running Certbot, your domain should be set up to accept traffic on https and port 443.

#### Test connection

You should now be able to connect to `https://your.domain` in the browser and be able to use the site. To ensure proper configuration, test voice chat and notification support.

## Making Your Instance Invite-only

Add the following section to your `Revolt.toml` file:
```toml
[api.registration]
# Whether an invite should be required for registration
# See https://github.com/stoatchat/self-hosted#making-your-instance-invite-only
invite_only = true
```

Create an invite:

```bash
# drop into mongo shell
docker compose exec database mongosh

# create the invite
use revolt
db.invites.insertOne({ _id: "enter_an_invite_code_here" })
```

## Enabling the Gif Picker

To enable the gif picker, you must create a Gifbox account and create an api key. Go to [gifbox.me](https://gifbox.me) and make an account. After creating an account and logging in, go to your account settings page by clicking your email in the top right. On your settings page, create an api key. Copy the api key and put it on the bottom of your secrets.env file like so:

```bash

REVOLT__API__SECURITY__TENOR_KEY='<yourapikey>'
```

Restart the stoat-gifbox service by running `docker compose down gifbox && docker compose up -d gifbox`.

The gifpicker should now work.
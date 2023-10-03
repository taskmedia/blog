---
title: "Control RPi GPIO throught standalone and offline WiFi (access point)"
date: 2023-10-03T10:30:45+02:00

tags:
  [
    "raspberry pi",
    "rpi",
    "access point",
    "wifi",
    "wlan",
    "dns",
    "python",
    "RaspAp",
  ]
author: "Marco"
---

## Background

Currently I have a servo connected to my RPi which should be controlled via Smartphone.
The easiest way for sure is just connect the Raspberry Pi with your home network and connect via IP address given to the RPi from your DHCP.

But in my setup this Raspberry is not always connected to the network and should be independently controllable.
Therefore I needed to go for another solution.

## TL;DR

I created an access point on the RPi and forwarded all traffic to the local web server.
The redirect is done by providing a custom DNS which redirects all traffic to itself.

## Solution

### Website

To control my servomotor I created a small website which is hosted on the Raspberry Pi.
When accessing a page there are three buttons to control the connected device: "up", "down" and "stop".
When a button is clicked the python script connects to the GPIO pins and sends the signal to control the servo.

This website is hosted locally on the RPi at port 80 with [Flask](https://pypi.org/project/Flask/).
To control the servomotor I use the [RPi.GPIO](https://pypi.org/project/RPi.GPIO/) library.

Accessing this website is possible when connection to the IP address or using the hostname in the local network.

To ensure the python script is always running I created a systemd service which is started on boot.

### Access point

But for my usecase the local network is mostly not available and the website should be available.
Therefore I created an access point on the Raspberry Pi which allows you to connect to the RPi directly.

When connected to the access point the website is available when connecting to the IP address of the Pi.

To create the access point I used [RaspAP](https://raspap.com/).
This is a web interface which allows you to create an access point on the Raspberry Pi.
It also allows you to configure the DHCP server and a DNS server for ad blocking with a denylist.

### DNS server

When connecting to the Pi via the access point you manually need to enter the IP address.
This might not be easy for everyone and therefore I used the given DNS server from RaspAP to redirect all traffic to the IP address of the Pi.

This will result in the following behavior:
On your smartphone you connect to the WiFi of the Raspberry Pi.
When connected a (splash) screen will be automatically presented (which will also be displayed in hotel WiFis to enter your name / room number).
Instead of clicking this obvious connect button you will directly be presented with the servo control website hosted on the RPi.

Even when the website is not shown all browser requests will be forwarded to the local web server.
This might not be best or safest soluton by sending wrong ip records - but easy to implement.
An internet access is not given therefore every request would otherwise fail.

## Setup

## Install RaspAP

Installing the access point is pretty easy.

```bash
curl -sL https://install.raspap.com | bash
```

During the run of the installation script you will be promted multiple times.
I accepted every installation except the VPNs (OpenVPN, WireGuard).
Ensure the ad blocking is also installed (DNS).

After the installation you can access the web interface on port 80.
To be able to run the python web server on port 80 we need to change this to e.g. 8080.
Therefore edit the `server.port` parameter in `/etc/lighttpd/lighttpd.conf` to your desired port.
Reboot or just restart the lighttpd service.

## Configure RaspAP

After the installation is completed you can access the web interface.
In my case this is `http://servopi.local:8080/`.
RaspAP is secured by BasicAuth with the credentials `admin:secret`.
You should change that in the settings later - but for now we just move on.

To customize the access point go to the `Hotspot` tab.
Change the name of the SSID to your desired name - e.g. `servo`.
On the Security tab you can change to a diffenent type or even disable the security at all.

To ensure the DNS will used when connected to the WiFi go to the `DHCP Server` tab and enter the IP address of the RPi of the wlan interface (`10.3.141.1`) as DNS server 1.
Due this change the ad blocking will be enabled but this will change later so every traffic will be _blocked_.

## Python web server

### Python preparation

I needed to install the latest python version (removed all other versions prior) and install the required python packages (flask and RPi.GPIO):

```bash
apt-get remove python\*
apt-get autoremove
apt install python3-pip

pip install -r requirements.txt
```

### Python script

The basic flask code will be like this:

```python
#!/bin/python3

from flask import Flask
# import RPi.GPIO as GPIO

app = Flask(__name__)


@app.route('/')
def html_root():
    return 'hello'


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
```

Test the script by running `python3 weberver.py`

### Systemd service

To ensure the python script is always running we need to create a systemd service.

Create a file in your local directory and link it later with systemctl as I did or create the file directly in `/etc/systemd/system/servoPi.service` with the following content:

```ini
[Unit]
Description=servo control
After=network.target
StartLimitIntervalSec=0
[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=/root/servoPi/run.sh
; ExecStopPost=/root/servoPi/stop.sh

[Install]
WantedBy=multi-user.target
```

The `run.sh` just uses some checks and runs the python script above.
Optionally you can add a _ExecStopPost_ as I did to ensure the servo will be at a certain position when the script is stopped.

To ensure the service is up and running you can use the following commands:

```bash
systemctl link /root/servoPi/servopi.service
systemctl daemon-reload
systemctl start servopi.service
systemctl status servopi.service
systemctl enable servopi.service
```

## DNS redirect

After the python web server and access point is up and running we need to redirect all traffic to the local web server.

Therefore we use the existing domain name server and add a configuration.

To be able to check the records we use dig:

```bash
apt install dnsutils
dig +short @1.1.1.1 github.com
dig +short @10.3.141.1 github.com
```

The correct IP address should be returned.
But now we will change the behavior of the DNS server to always return the Raspberry Pi wlan0 IP address:

```bash
echo "address=/#/10.3.141.1" > /etc/dnsmasq.d/010_redirect-servopi.conf
systemctl restart dnsmasq.service
```

_Warning:_ This will also redirect all other requests - you might not be longer able to fetch anything (even with apt or curl) from the internet.
To temporary fix this you just can disable the dns with `systemctl stop dnsmasq.service`.

To check the DNS records again you can use the following command:

```bash
dig +short @1.1.1.1 github.com
dig +short @10.3.141.1 github.com
```

You now can connect from your mobile phone to the Raspberry Pi access point and control the servo.
Remember that your device will not longer be able to browse the internet.

# Conclusion

This setup might be not ready for production and is more likely to be used for some fun projects.
I used this setup to let my friends easily control the servomoto in a safe environment.

Also the way with the DNS redirect might not be the best solution and you should just add e.g. a fictional hostname like `servo.pi` to the DNS and let the users manually enter this hostname in their browsers.

It also might be able to use a [captive portal](https://docs.raspap.com/captive/) instead.
Share your thought and ideas in the comments with me and the community.

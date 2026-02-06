# Wireguard Setup

## Motivation

Allow access to a home network from external networks by using a wireguard peer
as an 'insider' which allows access to hosts on the home network.

## Conceptual Overview

Wireguard is a peer-to-peer VPN technology which encapsulates network packets
over UDP to deliver them securely to the peer where they are decoded and
processed. The handling and redirection of packets is handled at the kernel
level (by the Wireguard kernel module). Packets reach the host on a network
interface, are passed to the wireguard module where they are decapsulated and
passed to the wireguard virtual interface. Once they reach the wireguard
interface they are handled like any other network packet reaching an interface
through (for example) passing to an application or forwarding via routing
rules.

## Steps

### Configuring the 'server'

The 'server' (i.e., the peer inside the home network) is configured by
generating a private and public key pair using:

```shell
wg genkey | tee priv.key | wg pubkey > pub.key
```

And generate the wireguard config:

```
[Interface]
# Address of the server and range of the virtual network
Address = 10.0.0.1/24
# Allow redirection of packets via wg0 onto local network
PostUp = ufw route allow in on wg0 out on eth0
# Enable masquerading (use the IP address of the server on the home network)
PostUp = iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on eth0
PreDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = 51820
PrivateKey = <priv-key-server>

[Peer]
# The IP address the peer will have on the network
AllowedIPs = 10.0.0.2/32
PublicKey = <pub-key-peer>
PersistentKeepAlive = 21
```

Note that in the server config we do not specify an endpoint for the peer
because it could connect from anywhere.

The corresponding config in the peer is:

```
[Interface]
Address = 10.0.0.2/32
# We can run dnsmasq on the wg server
DNS = 10.0.0.1
PrivateKey = <priv-key-peer>

[Peer]
# 10.0.100.0/24 is part of subnet mapping (see below)
AllowedIPs = 10.0.0.0/24, 10.0.100.0/24
# We can configure DDNS and use a hostname
Endpoint = <home-endpoint-ip-or-dns-name>:51820
PersistentKeepalive = 21
PublicKey = <pub-key-server>

```

The following network configurations must be set:

#### Enable IP forwarding

Edit `/etc/sysctl.conf`

```
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
```

To enable the wg0 interface to send packets to hosts in the home network via
(for example) eth0 which allows the server to act as a gateway.

#### Update firewall

The firewall (typically `ufw`) must be configured to allow access on the
relevant ports. Show rules using `ufw status numbered`. Allow access on port
51820/udp (wireguard) from anywhere and 53/udp and 53/tcp (DNS) from
10.0.0.0/24.

#### Update IP routing rules

If using `wg-quick` then these should be updated by the wireguard service based
on what's in the config file but you can check these using `ip route` to make
sure they're configured correctly. There should be entries for the
`10.0.0.0/24` network.

#### IP forwarding and DDNS

In order to actually reach the wireguard server on the home network from
anywhere we must configure the home network router to perform port forwarding
of requests from the WAN IP address for the home network on 51820 to 51820 on
the wireguard server host. This can typically be done for most routers via the
web interface for the router. Ensure that only 51820 is exposed. We do not
expose 53 because DNS requests will be sent over the VPN to the server via the
wireguard interface. Because most home IP addresses are not permanent, we
should set up DDNS to point at the latest WAN address for the home network.
This can be maintained by a service running on the wireguard server.
Here's some config for checking the WAN IP of the home network and
updating NoIP if it changes.

`/etc/systemd/system/ddns-update.service`

```
[Unit]
Description=Update No-IP DDNS
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ddns-update.sh
WorkingDirectory=/usr/local/bin/
EnvironmentFile=/etc/ddns-update.env
User=ddns-agent

[Install]
WantedBy=timers.target
```

`/etc/systemd/system/ddns-update.timer`

```
[Unit]
Description=Timer for No-IP DDNS update

[Timer]
OnCalendar=*:0/3:00
Persistent=true

[Install]
WantedBy=timers.target
```

`/usr/local/bin/ddns-update.sh`

```
#!/bin/bash -eu

CURRENT_IP=$(curl -s ifconfig.me)

if [ -f "${LAST_IP_FILE}" ]; then
  LAST_IP=$(cat "${LAST_IP_FILE}")
fi

if [ "${CURRENT_IP:-}" != "${LAST_IP:-""}" ]; then
  echo "IP address changed. Updating DDNS..."
  curl -s -u "${NOIP_USER}:${NOIP_PASS}" "https://dynupdate.no-ip.com/nic/update?hostname=${HOSTNAME}"
  if [ $? -eq 0 ]; then
    echo "${CURRENT_IP}" > "${LAST_IP_FILE}"
    echo "DDNS updated successfully."
  else
    echo "DDNS update failed."
  fi
else
  echo "IP address unchanged."
fi

exit 0
```

#### Subnet mapping

If we are connected to a network using the same IP address range as the home
network then IP addresses will be ambiguous (or most likely we will not be able
to route to hosts on the home network since (for example) 192.168.1.1 will be
the local network router not the home network router). We can perform a subnet
mapping which allows the use of the same host but with a different subnet. So
for example the home network gets mapped 192.168.1.1 -> 10.0.100.1 - note that
the host bits are the same (subnet mask /24). This can be configured on the
server:

```
sudo iptables -t nat -A PREROUTING -i wg0 -d 10.0.100.0/24 -j NETMAP --to 192.168.1.0/24
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -d 192.168.1.0/24 -j MASQUERADE
```

This is setting up a prerouting rule which maps packets from 10.0.100.0/24 to
the same host on 192.168.1.0/24 (`-j NETMAP`). The latter rule sets up
masquerading to replace the IP address of the packet with the server's IP
address on the network so the target host can send a response (since it doesn't
know anything about 10.0.0.0/24).

```
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

The iptables rules will not survive restart. We use `iptables-persistent` to
ensure the rules survive reboot.

#### dnsmasq

We can run a DNS server on the wireguard server host which serves IP addresses
for a .home domain we can configure for IP addresses in 10.0.100.0 (our
netmapped home network). This will allow us to access hosts in the home network
via names we configure instead of 10.0.100.0/24 IP addresses. Config of dnsmasq
is out of scope of this document.

## Verifying and debugging

### tcpdump

Use `tcpdump` to inspect traffic on interfaces to see if packets are reaching
the interface or if the issue is upstream.

```
tcpdump -i wg0
```

### ping

Once the VPN is set up you should be able to ping 10.0.0.1 and 10.0.100.1.

### wg show

You can verify that the wg handshake is occurring by inspecting 'latest
handshake'. The most common cause of handshake failure if the packets are
reaching the interface is incorrectly configured keys or setting the Endpoint
or AllowedIPs incorrectly.

### dig with '@'

Often DNS can be correctly configured on the server but the client may have
settings which don't use the correct DNS server to resolve the .home domain.

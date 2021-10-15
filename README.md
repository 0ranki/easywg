# EasyWG
## *Very much a work in progress!*
### Wireguard config manager
#### What is this?
EasyWG is intended to be an easy way to manage Wireguard configurations.

Currently you only need to create an initial config file on the WG server 
that contains only a very basic interface, e.g.
```
[Interface]
Address = 10.0.0.1/24
Address = fd00::1/112
PrivateKey = 8LGeNH67dmDb6O6Fbui7iK4KsCZ596Ikd0woOsimS1g=
```

EasyWG can handle the rest. The script does the following:
- creates a random available address in the subnet defined in the
  WG configuration file
- shows a QR code to scan the config to mobile devices
- saves the config file for later use
- optionally prints it to STDOUT
- adds the client as peer to the WG network
- sets routing for it

#### Usage
```
./easywg.sh split wg0
./easywg.sh full wg0
```

- `wg0` is the name of the interface as shown by `wg` command
- `split/full` whether to generate a split or full tunnel
  (all traffic routed through the tunnel or just the WG network)

That's it.

#### Configuration (optional)
Configuration/override options include:
- Override automatically detecting the server WAN IP, useful e.g. when
  the server has multiple IP addresses
- Set the MTU
- Set DNS servers, no `DNS = ...` line will be added if this parameter
  is unset
- Override the automatic random IP generation
- Set additional addresses to Allowed IPs for split tunnels
- Set the directory to save client configuration files. Default is
  `/etc/wireguard/clients`
- Limit the client IP range, if you don't for some reason want to
  use the whole subnet.

There's plans to make these optionally work with command line flags.



This is a work in progress and done mostly as a hobby project. There are 
many ready solutions that do the same and possibly more, probably better.

Firewall management is not yet implemented, but instructions will be added
to this readme for the most common solutions (UFW/iptables, firewalld)

No plans to support Windows at this stage unfortunately.

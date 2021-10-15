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

EasyWG can handle the rest. This is a work in progress and done mostly
as a hobby project. There are many ready solutions that do the same and
possibly more.

Firewall management is not yet implemented, but instructions will be added
to this readme for the most common solutions (UFW/iptables, firewalld)

No plans to support Windows at this stage unfortunately.

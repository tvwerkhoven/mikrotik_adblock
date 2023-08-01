# MikroTik/EdgeOS/dnsmasq/VyOS/PowerDNS Adblock

Convert public domain block lists in a few formats to MikroTik RouterOS static 
DNS entries.

See also my blog posts:
* [EdgeRouter X adblock](https://www.vanwerkhoven.org/blog/2022/home-network-configuration/#adblock)
* [DNS-based adblocking on VyOS](https://www.vanwerkhoven.org/blog/2023/dns-based-adblocking-on-vyos/)

# Usage

## Generate adblock list

Edit script and configure which blocklists to use in preamble, then run the script with desired output format:

```sh
./mkadblock.sh <dnsmasq|mikrotik|vyos>
```

then send `adblock.all.*` to your DNS server (e.g. router).

## Install VyOS

See my blog post [DNS-based adblocking on VyOS](https://www.vanwerkhoven.org/blog/2023/dns-based-adblocking-on-vyos/)

## Install edgerouter/dnsmasq

Install on EdgeRouter, should be similar for other dnsmasq-based systems:
```sh
ssh edgerouterx
sudo mv adblock-sorted.dnsmasq.txt /etc/dnsmasq.d/
```

Restart dnsmasq:
```sh
/usr/sbin/dnsmasq --test
sudo /etc/init.d/dnsmasq restart
less /var/log/dnsmasq.log
```

## Install Mikrotik

Import blocklist:

	/import adblock.all.rsc

to import DNS rules.

## Clean up Mikrotik

To remove adblock domains, run

	/ip dns static remove [find type=NXDOMAIN]

Or match specific marker in e.g. comments

	/ip dns static remove [find comment="mikrotikadblock"]

# Filter lists

I compiled my own collection from https://filterlists.com/ and https://v.firebog.net/hosts/lists.php Since block lists could be malicious, I selected based on 'trust' and how widely lists were used (and thus hoping they get more scrutiny).

# Processing

This Bash script supports a few formats to convert publicly available lists to 
MikroTik/dnsmasq/PowerDNS format. Also, I use this to document my way of working for future use.

# Resource consumption

## Mikrotik

An RB2011 with 100 of 128 MB free RAM can support ~30k domains.

When loading 50k domains: loading took 3.5min, free RAM went from ~100MB to 5.5 MB (although RAM was already at 5 MB for a while)
When loading 15k domains: loading took 1 min, free RAM went from ~100MB to 55 MB.

## Edgerouter X

dnsmasq claims to be quite fast:

> It is possible to use dnsmasq to block Web advertising by using a list of known banner-ad servers, all resolving to 127.0.0.1 or 0.0.0.0, in /etc/hosts or an additional hosts file. The list can be very long, dnsmasq has been tested successfully with one million names. That size file needs a 1GHz processor and about 60Mb of RAM. 

Without block list, I get query times of 7-25 msec for new domains, and 2-4 msec for cached domains (using `drill aa.com | grep "Query time"`). After adding 60k blocked domains, I get 80-110 msec for new domains and 2-4msec for cached domains. Performance doens't seem to matter whether I use NXDOMAIN or 127.0.0.1 or 0.0.0.0 blocking. Optimization is to increase cached domains (150 to max of 10000) and keep list to \~10k domains. This leads to \~30msec delay for new domains, and 2msec for cached domains (repeated query).

# Blocking methods

## Solution 1 - NXDOMAIN - optimal approach

Set domain resolution to NXDOMAIN (=Non eXisting)

Mikrotik example:
	/ip dns static add type=NXDOMAIN name="1-1ads.com"

Flow
1. Client queries DNS server
2. DNS server responds
3. Client stops request

Advantages:
- Minimal resource use on DNS server (no firewall rules triggered)
- Minimum round-trips
- No ambiguous effects associated with 127.0.0.1
- Elegant because this is what NXDOMAIN was meant for :)

## Solution 2 - 240.0.0.0/4

Set domain resolution to reserverd IP address. Requires additional firewall 
rule. Based on guide from [aziraphale](https://github.com/aziraphale/routeros-dns-adblock).

Mikrotik example:
	/ip dns static add address=240.0.0.1 name="1-1ads.com"
	/ip firewall filter add chain=forward in-interface=LAN connection-state=new protocol=tcp dst-address=240.0.0.0/4 action=reject reject-with=tcp-reset

Flow
1. Client queries DNS server
2. DNS server responds with 240.0.0.1
3. Client tries to connect to 240.0.0.1
4. Router responds with TCP-reset
5. Client stops request

## Solution 3 - 127.0.0.1

Commonly used but a poor solution: resolve domains to localhost (127.0.0.1) 
which might run a webserver, hopelessly delaying a simple blocking action.

Mikrotik example:
	/ip dns static add address=127.0.0.1 name="1-1ads.com"

Flow
1. Client queries DNS server
2. DNS server responds with 127.0.0.1
3. Client tries to connect to 127.0.0.1
4. Client could responds with TCP-reset, but could also be running a web server
5. ???

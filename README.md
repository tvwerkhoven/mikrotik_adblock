# MikroTik Adblock

Convert public domain block lists in a few formats to MikroTik RouterOS static 
DNS entries.

# Usage

## Install

Configure which blocklists to use in preamble, run script, send file to router 
and use

	/import adblock.all.rsc

to import DNS rules. You might want to tweak more than that though.

## Clean up

To remove adblock domains, run

	/ip dns static remove [find type=NXDOMAIN]

Or match specific marker in e.g. comments

	/ip dns static remove [find comment="mikrotikadblock"]

# Filter lists

I compiled my own collection from https://filterlists.com/ and https://v.firebog.net/hosts/lists.php Since block lists could be malicious, I selected based on 'trust' and how widely lists were used (and thus hoping they get more scrutiny).

# Processing

This Bash script supports a few formats to convert publicly available lists to 
MikroTik format. Also, I use this to document my way of working for future use.

# Resource consumption

An RB2011 with 100 of 128 MB free RAM can support ~30k domains.

When loading 50k domains: loading took 3.5min, free RAM went from ~100MB to 5.5 MB (although RAM was already at 5 MB for a while)
When loading 15k domains: loading took 1 min, free RAM went from ~100MB to 55 MB.

# Blocking methods

## Solution 1 - NXDOMAIN - optimal approach

Set domain resolution to NXDOMAIN (=Non eXisting)

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

	/ip dns static add address=127.0.0.1 name="1-1ads.com"

Flow
1. Client queries DNS server
2. DNS server responds with 127.0.0.1
3. Client tries to connect to 127.0.0.1
4. Client could responds with TCP-reset, but could also be running a web server
5. ???

#!/usr/bin/env bash
# 
# Make VyOS / powerdns DNS NXDOMAIN block list based on hosts and other
# filter lists
#
# # Blocking approach
# 
# Solution 1 (preferred):
# /ip dns static
# add type=NXDOMAIN name="1-1ads.com"
# 
# Solution 2 (requires additional tcp-reset firewall filter):
# /ip dns static
# add address=240.0.0.1 name="1-1ads.com"
#
# Solution 3 (worst, might redirect to local webserver):
# /ip dns static
# add address=127.0.0.1 name="1-1ads.com"

# check if curl or wget is installed
CURL_INSTALLED=false
WGET_INSTALLED=false
command -v curl >/dev/null 2>&1 && CURL_INSTALLED=true
command -v wget >/dev/null 2>&1 && WGET_INSTALLED=true

OUTFILE=$(date "+%Y%m%d")_adblock.all.vyos.txt

# Select which lists to use
# USELISTS=(list.disconnect.*.disc.txt list.adaway.hosts.txt list.adguard.hosts.txt list.yoyo.hosts.txt list.easylistdutch.tpl.txt)
# USELISTS=(list.yoyo.hosts.txt list.easylistdutch.tpl.txt)
USELISTS=(list.adaway.hosts.txt list.adguardmobilespyware.hosts.txt list.adguardmobileads.hosts.txt list.easylistdutch.tpl.txt list.yoyo.hosts.txt list.oisd.dnsmasq.txt)
USELISTS=(list.adguardmobilespyware.hosts.txt list.adguardmobileads.hosts.txt  list.oisd.dnsmasq.txt)

# Collect source lists
collect_source_list() {
	local url="${1}"
	local filename="${2}"
	if [ ${CURL_INSTALLED} = true ]; then
		test -f "${filename}" || curl "${url}" --silent -o "${filename}"
	elif [ ${WGET_INSTALLED} = true ]; then
		test -f "${filename}" || wget "${url}" --quiet -O "${filename}"
	fi
	wc -l "${filename}"
}

# Take out disconnect lists - see https://github.com/pi-hole/pi-hole/issues/3450
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt" "list.disconnect.simple_ad.disc.txt"
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt" "list.disconnect.simple_tracking.disc.txt"
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt" "list.disconnect.simple_malvertising.disc.txt"
collect_source_list "https://adaway.org/hosts.txt" "list.adaway.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardDNS.txt" "list.adguarddns.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileSpyware.txt" "list.adguardmobilespyware.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileAds.txt" "list.adguardmobileads.hosts.txt"
collect_source_list "https://easylist-msie.adblockplus.org/easylistdutch.tpl" "list.easylistdutch.tpl.txt"
collect_source_list "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"  "list.yoyo.hosts.txt"
collect_source_list "https://small.oisd.nl/dnsmasq" "list.oisd.dnsmasq.txt"


### Process for VyOS / PowerDNS
# See https://gist.github.com/ahupowerdns/bb1a043ce453a9f9eeed and https://www.vanwerkhoven.org/blog/2023/dns-based-adblocking-on-vyos/

rm -f /tmp/adblock.all.vyos.txt
rm -f ${OUTFILE}

# Format should be like return{"101com.com", "101order.com"}
echo -n "return{\"101com.com\"" >> ${OUTFILE}

# Process disconnect-format lists
for f in list.*.disc.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep -v \^\# $f | grep -v "localhost" | awk '{print ", \""$1"\""}' >> /tmp/adblock.all.vyos.txt
done

# Process hosts-format lists
for f in list.*.hosts.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep -v \^\# $f | grep -v "localhost" | awk '{print ", \""$2"\""}' >> /tmp/adblock.all.vyos.txt
done

# Process hosts-format lists
for f in list.*.dnsmasq.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep -v \^\# $f | awk -F  "/" '{print ", \""$2"\""}' >> /tmp/adblock.all.vyos.txt
done

# Process TPL-format lists
# https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/hh273399(v=vs.85)?redirectedfrom=MSDN#creatingtpls
# https://www.malwaredomainlist.com/forums/index.php?topic=4517.0
for f in list.*.tpl.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep "^-d" "$f" | awk 'NF<3 {print ", \""$2"\""}' >> /tmp/adblock.all.vyos.txt
done

# Filter out duplicates, count, skip first line because it's an empty host (usually)
sort /tmp/adblock.all.vyos.txt | uniq | tail -n +2 | tr -d '\n' >> ${OUTFILE}
wc -w ${OUTFILE}

echo "}" >> ${OUTFILE}

echo "to deploy:"
echo "scp ${OUTFILE} vyos:/config/scripts/pdns-adblock-blocklist.lua"
echo "vyos: restart dns forwarding"
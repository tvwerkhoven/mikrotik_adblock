#!/usr/bin/env bash
# 
# Make DNS block list based on various filter lists using NXDOMAIN method.
#
# Usage:
# ./mkadblock.sh <dnsmasq|mikrotik|vyos>
#

# Select which lists to use, from list below
# USELISTS=(list.adaway.hosts.txt list.adguardmobilespyware.hosts.txt list.adguardmobileads.hosts.txt list.yoyo.hosts.txt list.oisd.dnsmasq.txt)
USELISTS=(list.yoyo.hosts.txt list.oisd.dnsmasq.txt)

# Output format
OUTFORMATS=(dnsmasq mikrotik vyos)
if [[ ! ${OUTFORMATS[*]} =~ ${1} ]] then
	echo 'Usage: ./mkadblock.sh <dnsmasq|mikrotik|vyos>'
	exit 1
fi
OUTFORMAT=${1}

# check if curl or wget is installed
CURL_INSTALLED=false
WGET_INSTALLED=false
command -v curl >/dev/null 2>&1 && CURL_INSTALLED=true
command -v wget >/dev/null 2>&1 && WGET_INSTALLED=true

# Collect source lists
collect_source_list() {
	local url="${1}"
	local filename="${2}"
	rm -f /tmp/adblock_newlist.txt
	if [[ ${CURL_INSTALLED} = true ]]; then
		test -f "${filename}" || curl "${url}" --silent -o /tmp/adblock_newlist.txt
	elif [[ ${WGET_INSTALLED} = true ]]; then
		test -f "${filename}" || wget "${url}" --quiet -O /tmp/adblock_newlist.txt
	fi
	# Check if file is big enough (e.g. oisd has rate limiting which might return an empty file)
	if [[ -f "/tmp/adblock_newlist.txt" ]]; then
		len=$(test  && wc -l < /tmp/adblock_newlist.txt)
		if [[ $len -gt 500 ]]; then
			mv /tmp/newlist "${filename}"
			wc -l "${filename}"
		else
			echo "warning: file too small, not used ($filename)"
		fi
	fi
}

# Process source lists into output format
process_source_list() {
	echo "making ${OUTFORMAT} formatted list"
	# Process disconnect-format lists
	for f in list.*.disc.txt; do
		[[ ${USELISTS[*]} =~ "$f" ]] && echo "using list $f" && grep -v -e \^\# -e "localhost" -e '^$' $f | awk "${FMT_DISCONNECT}" >> /tmp/adblock.all.tmp
	done

	# Process hosts-format lists
	for f in list.*.hosts.txt; do
		[[ ${USELISTS[*]} =~ "$f" ]] && echo "using list $f" && grep -v -e "localhost" -e '^$' $f | awk "${FMT_DNSMASQ}" >> /tmp/adblock.all.tmp
	done

	# Process TPL-format lists
	# https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/hh273399(v=vs.85)?redirectedfrom=MSDN#creatingtpls
	# https://www.malwaredomainlist.com/forums/index.php?topic=4517.0
	for f in list.*.tpl.txt; do
		[[ ${USELISTS[*]} =~ "$f" ]] && echo "using list $f" && grep "^-d" "$f" | awk "${FMT_TPL}" >> /tmp/adblock.all.tmp
	done

	for f in list.*.dnsmasq.txt; do
		[[ ${USELISTS[*]} =~ "$f" ]] && echo "using list $f" && grep -v -e "localhost" -e '^$' "$f" | awk "${FMT_DNSMASQ}" >> /tmp/adblock.all.tmp
	done

	# Filter out duplicates, count
	sort /tmp/adblock.all.tmp | uniq >> adblock.all.${OUTFORMAT}.txt

	wc -l adblock.all.${OUTFORMAT}.txt
}

# Take out disconnect lists - see https://github.com/pi-hole/pi-hole/issues/3450
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt" "list.disconnect.simple_ad.disc.txt"
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt" "list.disconnect.simple_tracking.disc.txt"
#collect_source_list "https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt" "list.disconnect.simple_malvertising.disc.txt"
collect_source_list "https://adaway.org/hosts.txt" "list.adaway.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardDNS.txt" "list.adguarddns.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileSpyware.txt" "list.adguardmobilespyware.hosts.txt"
collect_source_list "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileAds.txt" "list.adguardmobileads.hosts.txt"
# collect_source_list "https://easylist-msie.adblockplus.org/easylistdutch.tpl" "list.easylistdutch.tpl.txt" Dead link
collect_source_list "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"  "list.yoyo.hosts.txt"
collect_source_list "https://small.oisd.nl/dnsmasq" "list.oisd.dnsmasq.txt"

wc -l list*txt

rm -f /tmp/adblock.all.tmp
rm -f adblock.all.${OUTFORMAT}.txt

if [[ ${OUTFORMAT} = "dnsmasq" ]]; then
	# Output format: address=/<FQDN>/
	FMT_DISCONNECT='{print "address=/"$1"/"}'
	FMT_HOST='{print "address=/"$2"/"}'
	FMT_TPL='NF<3 {print "address=/"$2"/"}'
	FMT_DNSMASQ='BEGIN { FS="/" } {print "address=/"$2"/"}'
	process_source_list
elif [[ ${OUTFORMAT} = "mikrotik" ]]; then
	# Output format: add type=NXDOMAIN comment=mikrotikadblock name="FQDN"
	echo "/ip dns static" > adblock.all.${OUTFORMAT}.txt

	FMT_DISCONNECT='NF {print "add type=NXDOMAIN comment=mikrotikadblock name=\""$0"\""}'
	FMT_HOST='NF {print "add type=NXDOMAIN comment=mikrotikadblock name=\""$2"\""}' 
	FMT_TPL='NF<3 {print "add type=NXDOMAIN comment=mikrotikadblock name=\""$2"\""}'
	FMT_DNSMASQ='BEGIN { FS="/" } {print "add type=NXDOMAIN comment=mikrotikadblock name=\""$2"\""}'
	process_source_list

	# Add success message
	cat << EOF >> adblock.all.${OUTFORMAT}.txt
/put "Script reached end successfully. Total entries:"
/ip dns static print count-only
EOF

elif [[ ${OUTFORMAT} = "vyos" ]]; then
	# Format should be like return{"<FQDN1>", "<FQDN2>"}	
	echo -n "return{\"101com.com\"" >> adblock.all.${OUTFORMAT}.txt

	FMT_DISCONNECT='{print ", \""$1"\""}'
	# FMT_DISCONNECT='{printf(", \"%s\"",$1)}'
	FMT_HOST='{print ", \""$2"\""}'
	# FMT_HOST='{printf(", \"%s\"",$2)}'
	FMT_TPL='NF<3 {print ", \""$2"\""}'
	# FMT_TPL='NF<3 {printf(", \"%s\"",$2)}'
	FMT_DNSMASQ='BEGIN { FS="/" } {print ", \""$2"\""}'
	process_source_list

	echo -n $(tr -d "\n" < adblock.all.${OUTFORMAT}.txt) > adblock.all.${OUTFORMAT}.txt

	echo "}" >> adblock.all.${OUTFORMAT}.txt
else
	echo "Unknown format, shouldn't happen"
	exit 1
fi

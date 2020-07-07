#!/usr/bin/env bash
# 
# Make MikroTik / RouterOS DNS NXDOMAIN block list based on hosts and other
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

# Select which lists to use
# USELISTS=(list.disconnect.*.disc.txt list.adaway.hosts.txt list.adguard.hosts.txt list.yoyo.hosts.txt list.easylistdutch.tpl.txt)
# USELISTS=(list.yoyo.hosts.txt list.easylistdutch.tpl.txt)
USELISTS=(list.disconnect.*.disc.txt list.adaway.hosts.txt list.yoyo.hosts.txt list.easylistdutch.tpl.txt)

# Collect source lists
test -f list.disconnect.simple_ad.disc.txt || wget https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt -O list.disconnect.simple_ad.disc.txt
test -f list.disconnect.simple_tracking.disc.txt || wget https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt -O list.disconnect.simple_tracking.disc.txt
test -f list.disconnect.simple_malvertising.disc.txt || wget https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt -O list.disconnect.simple_malvertising.disc.txt
test -f list.adaway.hosts.txt || wget https://adaway.org/hosts.txt -O list.adaway.hosts.txt
test -f list.adguard.hosts.txt || wget https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardDNS.txt -O list.adguard.hosts.txt
test -f list.yoyo.hosts.txt || wget "https://pgl.yoyo.org/as/serverlist.php?showintro=0;hostformat=hosts" -O list.yoyo.hosts.txt
test -f list.easylistdutch.tpl.txt || wget "https://easylist-msie.adblockplus.org/easylistdutch.tpl" -O list.easylistdutch.tpl.txt

cat << EOF > adblock.all.rsc
/ip dns static
EOF

rm -f /tmp/adblock.all.lists.rsc

# Process disconnect-format lists
for f in list.*.disc.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep -v \# $f | grep -v "localhost" | awk 'NF {print "add type=NXDOMAIN name=\""$0"\""}' >> /tmp/adblock.all.lists.rsc
done

# Process hosts-format lists
for f in list.*.hosts.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep -v ^# $f | grep -v "localhost" | awk 'NF {print "add type=NXDOMAIN name=\""$2"\""}' >> /tmp/adblock.all.lists.rsc
done

# Process TPL-format lists
# https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/hh273399(v=vs.85)?redirectedfrom=MSDN#creatingtpls
# https://www.malwaredomainlist.com/forums/index.php?topic=4517.0
for f in list.*.tpl.txt; do
	[[ ${USELISTS[*]} =~ "$f" ]] && grep "^-d" "$f" | awk 'NF<3 {print "add type=NXDOMAIN name=\""$2"\""}' >> /tmp/adblock.all.lists.rsc
done

# FUTURE: filter out CNAME records, only keep A and AAAA records to compress list. CNAMEs will automatically link to A records anyway.
# while read line; do
# 	${line:25:10}"; 
# done < /tmp/adblock.all.lists.rsc
# dig @8.8.8.8 +noall +answer www-googletagmanager.l.google.com CNAME

# Filter out duplicates
sort /tmp/adblock.all.lists.rsc | uniq >> adblock.all.rsc

# Add success message

cat << EOF >> adblock.all.rsc
/put "Script reached end successfully. Total entries:"
/ip dns static print count-only
EOF

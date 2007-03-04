#!/bin/sh
#
# If we have an unicast .local domain, we immediately disable avahi to avoid
# conflicts with the multicast IP4LL .local domain
DISABLE_TAG_DIR="/var/run/avahi-daemon/"
DISABLE_TAG="$DISABLE_TAG_DIR/disabled-for-unicast-local"

AVAHI_DAEMON_DETECT_LOCAL=1

test -f /etc/default/avahi-daemon && . /etc/default/avahi-daemon

if [ "$AVAHI_DAEMON_DETECT_LOCAL" != "1" ]; then
  exit 0
fi


dns_has_local() { 
  # If there are no nameserver entries in resolv.conf there are no unicast
  # .local domains :)
  $(grep -q nameserver /etc/resolv.conf) || return 1;

  # If there is no local nameserver and no we have no global ip addresses
  # then there is no need to query the nameservers
  if ! $(egrep -q "nameserver 127.0.0.1|::1" /etc/resolv.conf); then 
    # Get addresses of all running interfaces
    ADDRS=$(ifconfig | grep ' addr:')
    # Filter out all local addresses
    ADDRS=$(echo "${ADDRS}" | egrep -v ':127|Scope:Host|Scope:Link')
    if [ -z "${ADDRS}" ] ; then
      return 1;
    fi
  fi

  OUT=`LC_ALL=C host -t soa local. 2>&1`
  if [ $? -eq 0 ] && echo "$OUT" | egrep -vq 'has no|not found'; then
    return 0
  fi
  return 1
}

if dns_has_local ; then
    if [ -x /etc/init.d/avahi-daemon ]; then
        /etc/init.d/avahi-daemon stop || true
        if [ -x /usr/bin/logger ]; then
            logger -p daemon.warning -t avahi <<EOF
Avahi detected that your currently configured local DNS server serves
a domain .local. This is inherently incompatible with Avahi and thus
Avahi disabled itself. If you want to use Avahi in this network, please
contact your administrator and convince him to use a different DNS domain,
since .local should be used exclusively for Zeroconf technology.
For more information, see http://avahi.org/wiki/AvahiAndUnicastDotLocal
EOF
        fi
    fi
    if [ ! -d ${DISABLE_TAG_DIR} ] ; then 
      mkdir -m 0755 -p ${DISABLE_TAG_DIR}
      chown avahi:avahi ${DISABLE_TAG_DIR}
    fi 
    touch ${DISABLE_TAG}
else
    # no unicast .local conflict, so remove the tag and start avahi again
    if [ -e ${DISABLE_TAG} ]; then
        rm -f ${DISABLE_TAG}
        if [ -x /etc/init.d/avahi-daemon ]; then
            /etc/init.d/avahi-daemon start || true
        fi
    fi
fi

exit 0

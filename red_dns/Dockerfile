# red_dns — 4 nodos Ubuntu 24.04 con systemd y BIND 9 (ns1, ns2, resolutor, cliente) para los labs 7 y 8.
# Usa systemd igual que el servidor de los labs 2-5, para que funcionen systemctl, rndc y journalctl -u named.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=America/La_Paz
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus tzdata ca-certificates \
      bind9 bind9-utils dnsutils iproute2 iputils-ping nano less \
    && find /etc/systemd/system /lib/systemd/system -path '*.wants/*' \
         \( -name '*getty*' -o -name 'systemd-logind*' \) -delete || true \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

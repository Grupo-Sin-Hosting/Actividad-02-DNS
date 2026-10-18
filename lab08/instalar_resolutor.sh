#!/usr/bin/env bash
# instalar_resolutor.sh — Unbound como resolutor del colegio. Ejecutar EN el nodo resolutor:
#   docker compose exec resolutor bash /lab/lab08/instalar_resolutor.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (o con sudo)"; exit 1; }

# 1. Ancla de confianza de la raíz para DNSSEC (unbound-anchor la descarga/verifica; si no hay red usa dns-root-data)
install -d -o unbound -g unbound /var/lib/unbound
unbound-anchor -a /var/lib/unbound/root.key || true
chown unbound:unbound /var/lib/unbound/root.key

# 2. Configuración y lista RPZ
install -m 644 unbound/horizonte-resolutor.conf /etc/unbound/unbound.conf.d/
install -m 644 unbound/rpz.horizonte.internal /etc/unbound/

# 3. DNSControl (DNS como código) para la Parte E — versión fija para que todos tengan la misma
if ! command -v dnscontrol >/dev/null; then
  curl -sL -o /tmp/dnscontrol.deb https://github.com/DNSControl/dnscontrol/releases/download/v5.2.0/dnscontrol-5.2.0.amd64.deb     && dpkg -i /tmp/dnscontrol.deb >/dev/null || echo "⚠️  No se pudo instalar DNSControl (¿sin internet?)"
fi

# 4. Validar y aplicar
unbound-checkconf
systemctl enable unbound >/dev/null 2>&1
systemctl restart unbound
sleep 2
systemctl is-active unbound
echo "Resolutor listo: dig @10.10.10.4 www.horizonte.internal"

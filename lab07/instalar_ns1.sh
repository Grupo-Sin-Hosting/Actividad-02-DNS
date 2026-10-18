#!/usr/bin/env bash
# instalar_ns1.sh — Configura ns1 como PRIMARIO de horizonte.internal.  Ejecutar EN ns1:  bash /lab/lab07/instalar_ns1.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (o con sudo)"; exit 1; }

# 1. Clave TSIG compartida (se crea una sola vez; ns2 la leerá de compartido/)
install -d -m 755 compartido
if [[ ! -s compartido/transferencia.key ]]; then
  tsig-keygen -a hmac-sha256 transferencia-horizonte > compartido/transferencia.key
fi
install -o root -g bind -m 640 compartido/transferencia.key /etc/bind/transferencia.key

# 2. Configuración y zonas (las zonas van en /var/lib/bind: BIND puede escribir ahí)
install -o root -g bind -m 644 ns1/named.conf.options ns1/named.conf.local /etc/bind/
install -o bind -g bind -m 644 ns1/db.horizonte.internal ns1/db.10.10.10 /var/lib/bind/

# 3. Validar ANTES de aplicar
named-checkconf
named-checkzone horizonte.internal /var/lib/bind/db.horizonte.internal
named-checkzone 10.10.10.in-addr.arpa /var/lib/bind/db.10.10.10

# 4. Aplicar
systemctl enable named >/dev/null 2>&1
if systemctl is-active -q named; then rndc reload; else systemctl start named; fi
sleep 1
echo "ns1 listo: dig @10.10.10.2 www.horizonte.internal"

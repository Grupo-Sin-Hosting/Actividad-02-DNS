#!/usr/bin/env bash
# instalar_ns2.sh — Configura ns2 como SECUNDARIO (copia las zonas de ns1).  Ejecutar EN ns2 DESPUÉS de ns1.
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (o con sudo)"; exit 1; }
[[ -s compartido/transferencia.key ]] || { echo "Falta compartido/transferencia.key: ejecuta primero instalar_ns1.sh en ns1"; exit 1; }

install -o root -g bind -m 640 compartido/transferencia.key /etc/bind/transferencia.key
install -o root -g bind -m 644 ns2/named.conf.options ns2/named.conf.local /etc/bind/
named-checkconf

systemctl enable named >/dev/null 2>&1
if systemctl is-active -q named; then rndc reload; else systemctl start named; fi
sleep 2
rndc zonestatus horizonte.internal | grep -E 'serial|type' || true
echo "ns2 listo: dig @10.10.10.3 www.horizonte.internal"

#!/usr/bin/env bash
# verificar_lab08.sh — Comprueba el resolutor del colegio y la zona pública como código. Ejecutar EN el resolutor:
#   docker compose exec resolutor bash /lab/lab08/verificar_lab08.sh
cd "$(dirname "$0")"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
R=10.10.10.4
res()    { dig +short @$R "$@" | tail -1; }
estado() { dig @$R "$@" | grep -o 'status: [A-Z]*' | cut -d' ' -f2; }
nodata() { local s; s=$(dig @$R "$1"); grep -q 'status: NOERROR' <<<"$s" && grep -q 'ANSWER: 0' <<<"$s"; }
validado()  { dig +dnssec @$R cloudflare.com SOA | grep -q 'flags:.* ad'; }
cache()     { dig @$R www.upds.edu.bo >/dev/null; [[ $(dig @$R www.upds.edu.bo | awk '/Query time/{print $4}') -le 2 ]]; }
sin_version(){ [[ -z "$(dig +short @$R CH TXT version.bind)" ]]; }
solo_dot()  {
  unbound-control flush_zone upds.edu.bo >/dev/null; unbound-control flush_zone gob.bo >/dev/null
  (timeout 6 tcpdump -ni eth0 -nn '(dst port 53 or dst port 853) and not dst net 10.10.10.0/24' 2>/dev/null > /tmp/v8.txt &)
  sleep 1; dig @$R www.upds.edu.bo >/dev/null; dig @$R www.gob.bo >/dev/null; sleep 6
  (( $(grep -c '\.853:' /tmp/v8.txt) > 0 && $(grep -c '\.53:' /tmp/v8.txt) == 0 ))
}
acceso_limitado(){ grep -rqs 'access-control: *0.0.0.0/0 *refuse' /etc/unbound/unbound.conf.d/; }
zona_codigo()   { local z=dns-como-codigo/zonas/ue-horizonte.example.zone; named-checkzone ue-horizonte.example $z && grep -q 'CAA' $z && grep -q '_dmarc' $z && ! grep -q default_not_set $z; }

revisar "Configuración válida (unbound-checkconf)"         unbound-checkconf
revisar "Unbound activo"                                    systemctl is-active unbound
revisar "www.horizonte.internal → 10.10.10.20 (stub-zone)"  test "$(res www.horizonte.internal)" = 10.10.10.20
revisar "portal (CNAME) resuelto hasta la IP"               test "$(res portal.horizonte.internal)" = 10.10.10.20
revisar "Inversa privada 10.10.10.25 → mail"                test "$(res -x 10.10.10.25)" = mail.horizonte.internal.
revisar "Resuelve internet (www.upds.edu.bo)"               test -n "$(res www.upds.edu.bo)"
revisar "DNSSEC validado (flag ad en cloudflare.com)"       validado
revisar "DNSSEC falso rechazado (dnssec-failed.org → SERVFAIL)" test "$(estado dnssec-failed.org)" = SERVFAIL
revisar "RPZ: apuestas-ejemplo.com → NXDOMAIN"              test "$(estado apuestas-ejemplo.com)" = NXDOMAIN
revisar "RPZ: subdominios también bloqueados"               test "$(estado juego.apuestas-ejemplo.com)" = NXDOMAIN
revisar "RPZ: phishing redirigido a la página de aviso"     test "$(res horizonte-notas-login.com)" = 10.10.10.20
revisar "RPZ: rastreador sin datos (NODATA)"                nodata rastreo.publicidad-ejemplo.net
revisar "Caché: segunda consulta en ≤ 2 ms"                 cache
revisar "Versión oculta"                                    sin_version
revisar "Acceso solo para la red del colegio"               acceso_limitado
revisar "Salida a internet solo cifrada (DoT :853, nada por :53)" solo_dot
revisar "Zona pública generada con DNSControl y válida"     zona_codigo
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]

#!/usr/bin/env bash
# verificar_lab07.sh — Comprueba el DNS autoritativo del colegio. Ejecutar en el nodo CLIENTE:
#   docker compose exec cliente bash /lab/lab07/verificar_lab07.sh
cd "$(dirname "$0")"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
NS1=10.10.10.2; NS2=10.10.10.3; Z=horizonte.internal
r()      { dig +short +norec @"$1" "${@:2}"; }
es()     { [[ "$(r "$1" "${@:2:$#-2}")" == "${@: -1}" ]]; }
aa()     { dig +norec @"$1" "$2" "${3:-A}" | grep -q 'flags:.* aa'; }
serial() { dig +short +norec @"$1" "$Z" SOA | awk '{print $3}'; }
axfr_sin_clave() { dig @"$NS1" "$Z" AXFR | grep -q 'Transfer failed'; }
axfr_con_clave() { dig -k compartido/transferencia.key @"$NS1" "$Z" AXFR | grep -q 'aula-lab'; }
sin_recursion()  { dig @"$NS1" google.com A | grep -q 'status: REFUSED'; }
version_oculta() { [[ "$(dig +short @"$NS1" CH TXT version.bind)" == '"no disponible"' ]]; }
nxdomain()       { dig +norec @"$NS1" noexiste.$Z A | grep -q 'status: NXDOMAIN'; }

revisar "ns1 responde www con autoridad (aa)"          aa $NS1 www.$Z
revisar "www.$Z → 10.10.10.20"                         es $NS1 www.$Z A 10.10.10.20
revisar "portal es alias (CNAME) de www"               es $NS1 portal.$Z CNAME www.$Z.
revisar "MX 10 mail.$Z"                                es $NS1 $Z MX "10 mail.$Z."
revisar "SPF: v=spf1 mx -all"                          es $NS1 $Z TXT '"v=spf1 mx -all"'
revisar "CAA presente"                                 bash -c "dig +short @$NS1 $Z CAA | grep -q issue"
revisar "Inversa: 10.10.10.25 → mail.$Z"               es $NS1 -x 10.10.10.25 mail.$Z.
revisar "Inversa: 10.10.10.20 → www.$Z"                es $NS1 -x 10.10.10.20 www.$Z.
revisar "Nombre inexistente → NXDOMAIN"                nxdomain
revisar "ns2 responde con autoridad (zona copiada)"    aa $NS2 www.$Z
revisar "ns2 tiene la inversa"                         es $NS2 -x 10.10.10.25 mail.$Z.
revisar "Mismo serial en ns1 y ns2"                    bash -c "[[ -n '$(serial $NS1)' && '$(serial $NS1)' == '$(serial $NS2)' ]]"
revisar "Transferencia SIN clave rechazada"            axfr_sin_clave
revisar "Transferencia CON clave TSIG permitida"       axfr_con_clave
revisar "ns1 no hace recursión (REFUSED a google.com)" sin_recursion
revisar "Versión de BIND oculta"                       version_oculta
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]

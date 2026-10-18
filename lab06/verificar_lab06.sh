#!/usr/bin/env bash
# verificar_lab06.sh — Comprueba tu radiografia_dns.sh contra dos dominios reales de referencia.
#   cloudflare.com: bien configurado (DNSSEC, CAA, IPv6, DMARC reject)
#   upds.edu.bo:    delegación con un NS que no responde, sin CAA ni DNSSEC, DMARC quarantine
# Son datos REALES de internet (revisados el 30/09/2026): si algo cambió, compáralo con dig y explícalo en tu hoja.
cd "$(dirname "$0")"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
CF=$(bash radiografia_dns.sh cloudflare.com 2>&1)
UP=$(bash radiografia_dns.sh upds.edu.bo 2>&1)
tiene() { grep -q -- "$2" <<<"$1"; }

revisar "El script no tiene errores de sintaxis"          bash -n radiografia_dns.sh
revisar "cloudflare.com: DNSSEC firmado y validado"      tiene "$CF" "✅ DNSSEC"
revisar "cloudflare.com: CAA detectado"                  tiene "$CF" "✅ CAA"
revisar "cloudflare.com: DMARC p=reject"                 tiene "$CF" "✅ DMARC con política p=reject"
revisar "cloudflare.com: IPv6 detectado"                 tiene "$CF" "✅ AAAA"
revisar "cloudflare.com: puntaje perfecto"               bash -c "grep -Eq 'Puntaje: ([0-9]+) de \1$' <<<\"\$0\"" "$CF"
revisar "upds.edu.bo: detecta el NS que no responde"     tiene "$UP" "❌ Delegación coja"
revisar "upds.edu.bo: detecta la diferencia padre/zona"  tiene "$UP" "⚠️  NS: el padre"
revisar "upds.edu.bo: sin CAA"                           tiene "$UP" "❌ CAA"
revisar "upds.edu.bo: sin DNSSEC"                        tiene "$UP" "❌ DNSSEC: no firmado"
revisar "upds.edu.bo: DMARC p=quarantine"                tiene "$UP" "✅ DMARC con política p=quarantine"
revisar "upds.edu.bo: aviso del RNAME del SOA"           tiene "$UP" "RNAME termina"
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]

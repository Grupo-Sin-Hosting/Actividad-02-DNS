#!/usr/bin/env bash
# radiografia_dns.sh — Diagnóstico de la salud DNS de un dominio (Tecnología Web I, Laboratorio 6).
# Uso:  bash radiografia_dns.sh <dominio>            ej.: bash radiografia_dns.sh upds.edu.bo
# Variable opcional RESOLUTOR (por defecto 1.1.1.1). En Docker no uses 127.0.0.11: no responde bien a la raíz.
set -uo pipefail

DOMINIO="${1:?Uso: bash radiografia_dns.sh <dominio>}"
DOMINIO="${DOMINIO%.}"
RES="${RESOLUTOR:-1.1.1.1}"
bien=0; total=0

ok()    { echo "✅ $*"; bien=$((bien + 1)); total=$((total + 1)); }
aviso() { echo "⚠️  $*"; total=$((total + 1)); }
mal()   { echo "❌ $*"; total=$((total + 1)); }
q()     { dig +short +time=3 +tries=1 @"$RES" "$@"; }

echo "Radiografía DNS de $DOMINIO (resolutor $RES) — $(date '+%Y-%m-%d %H:%M')"
echo "────────────────────────────────────────────────────────────"

# 1. Servidores de nombres: lo que dice la ZONA vs lo que dice el PADRE (la delegación)
NS_ZONA=$(q "$DOMINIO" NS | tr 'A-Z' 'a-z' | sort)
# El padre es la zona de arriba que tiene sus propios NS (edu.bo no los tiene: lo administra .bo)
PADRE="${DOMINIO#*.}"
while [[ "$PADRE" == *.* && -z $(q "$PADRE" NS) ]]; do PADRE="${PADRE#*.}"; done
NS_PADRE_SRV=$(q "$PADRE" NS | head -1)
NS_PADRE=$(dig +norec +time=3 +tries=1 @"$NS_PADRE_SRV" "$DOMINIO" NS | awk '$4=="NS"{print tolower($5)}' | sort -u)
[[ -z $NS_PADRE ]] && NS_PADRE="$NS_ZONA"     # si el padre es también autoritativo del hijo
if [[ -z $NS_ZONA ]]; then
  mal "NS: el dominio no tiene servidores de nombres (¿existe?)"; echo "Puntaje: 0"; exit 1
elif [[ "$NS_ZONA" == "$NS_PADRE" ]]; then
  ok "NS: $(echo $NS_ZONA | wc -w) servidores; la delegación del padre ($PADRE) coincide con la zona"
else
  aviso "NS: el padre ($PADRE) delega en [$(echo $NS_PADRE)] pero la zona declara [$(echo $NS_ZONA)]"
fi
if (( $(echo "$NS_ZONA" | wc -w) < 2 )); then mal "NS: menos de 2 servidores (sin redundancia)"; fi

# 2. ¿Responden todos los NS con autoridad y el mismo número de serie?
SERIALES=""; COJOS=""
for ns in $(echo "$NS_ZONA $NS_PADRE" | tr ' ' '
' | sort -u); do
  r=$(dig +norec +time=3 +tries=1 @"$ns" "$DOMINIO" SOA 2>/dev/null)
  # TODO: si la respuesta trae la bandera 'aa' (autoritativa) en la línea 'flags:', agrega el número de serie
  #       (7.º campo de la línea SOA) a SERIALES; si no, agrega "$ns " a COJOS.
  #       Pista: grep -q 'flags:.* aa' <<<"$r"   ·   awk '$4=="SOA"{print $7}' <<<"$r"
    if grep -q 'flags:.* aa' <<<"$r"; then
    SERIALES="$SERIALES $(awk '$4=="SOA"{print $7}' <<<"$r")"
  else
    COJOS="$COJOS$ns "
  fi
done
if [[ -z $COJOS ]]; then ok "Todos los NS responden con autoridad"; else mal "Delegación coja (lame): $COJOS no responde con autoridad"; fi
if [[ -z ${SERIALES// /} ]]; then
  mal "SOA: ningún NS respondió con autoridad"
elif [[ $(echo $SERIALES | tr ' ' '\n' | sort -u | wc -l) -eq 1 ]]; then
  ok "SOA: mismo número de serie en todos los NS ($(echo $SERIALES | cut -d' ' -f1))"
else
  mal "SOA: números de serie distintos entre NS ($SERIALES) — secundarios desactualizados"
fi

# 3. SOA: el correo del responsable (RNAME) — error clásico: olvidar el punto final
RNAME=$(q "$DOMINIO" SOA | awk '{print $2}')
RESTO="${RNAME%.$DOMINIO.}"
if [[ "$RESTO" != "$RNAME" && "$RESTO" =~ \.(com|net|org|bo|edu|gob|gov|io)$ ]]; then
  aviso "SOA: el RNAME termina en '...$(sed 's/^[^.]*//' <<<"$RNAME")' — ¿faltó el punto final en el archivo de zona?"
else
  ok "SOA: RNAME coherente ($RNAME)"
fi

# 4. Direcciones del sitio
A=$(q "$DOMINIO" A | tr '\n' ' '); AAAA=$(q "$DOMINIO" AAAA | tr '\n' ' ')
[[ -n $A ]]    && ok "A (IPv4): $A"       || aviso "A: el dominio raíz no tiene IPv4"
[[ -n $AAAA ]] && ok "AAAA (IPv6): $AAAA" || aviso "AAAA: sin IPv6"
W=$(q "www.$DOMINIO" A | tail -1)
[[ -n $W ]] && ok "www.$DOMINIO → $W" || aviso "www.$DOMINIO no resuelve"

# 5. Correo: MX, SPF y DMARC
MX=$(q "$DOMINIO" MX | sort -n | tr '\n' ';')
[[ -n $MX ]] && ok "MX: $MX" || aviso "MX: el dominio no recibe correo"
SPF=$(q "$DOMINIO" TXT | tr -d '"' | grep -i '^v=spf1' | head -1)
if [[ -z $SPF ]];              then mal "SPF: no existe (cualquiera puede enviar correo con este dominio)"
elif [[ $SPF == *"-all"* ]];   then ok "SPF estricto: $SPF"
else                                aviso "SPF sin '-all': $SPF"; fi
# TODO: DMARC — consulta el TXT de _dmarc.$DOMINIO, busca 'v=DMARC1' y su política (p=none|quarantine|reject).
#       Sin registro → mal "DMARC: no existe" · p=none → aviso "DMARC solo observa (p=none)"
#       otra → ok "DMARC con política p=…"
DMARC=$(q "_dmarc.$DOMINIO" TXT | tr -d '"' | grep -i '^v=DMARC1' | head -1)
POL=$(grep -o 'p=[a-z]*' <<<"$DMARC" | head -1)
if [[ -z $DMARC ]];         then mal "DMARC: no existe"
elif [[ $POL == "p=none" ]]; then aviso "DMARC solo observa (p=none)"
else                             ok "DMARC con política $POL"; fi

# 6. CAA: qué autoridades pueden emitir certificados
# TODO: CAA — consulta los registros CAA del dominio.
#       Con registros → ok "CAA: …" · sin registros → mal "CAA: sin registros (cualquier CA del mundo puede emitir certificados)"
CAA=$(q "$DOMINIO" CAA | tr '\n' ' ')
[[ -n $CAA ]] && ok "CAA: $CAA" || mal "CAA: sin registros (cualquier CA del mundo puede emitir certificados)"

# 7. DNSSEC: ¿hay DS en el padre y la respuesta viene validada (flag ad)?
# TODO: DNSSEC — consulta el DS del dominio (vive en el padre) y pide el SOA con +dnssec para ver si trae la bandera 'ad'.
#       DS y ad → ok "DNSSEC: firmado y validado (DS en $PADRE, flag ad)"
#       DS sin ad → mal "DNSSEC: hay DS pero la validación falla …"
#       sin DS → mal "DNSSEC: no firmado (sin DS en $PADRE)"
DS=$(q "$DOMINIO" DS)
R=$(dig +dnssec +time=3 +tries=1 @"$RES" "$DOMINIO" SOA)
if [[ -n $DS ]] && grep -q 'flags:.* ad' <<<"$R"; then
  ok "DNSSEC: firmado y validado (DS en $PADRE, flag ad)"
elif [[ -n $DS ]]; then
  mal "DNSSEC: hay DS pero la validación falla (firmas vencidas o claves que no coinciden)"
else
  mal "DNSSEC: no firmado (sin DS en $PADRE)"
fi

echo "────────────────────────────────────────────────────────────"
echo "Puntaje: $bien de $total"

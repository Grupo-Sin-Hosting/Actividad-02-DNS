# Bitácora de uso de IA — Laboratorio 7 (BIND9: primario, secundario y TSIG)

Estudiante: Lizeth Rodríguez · Entorno: red Docker `red_dns` (Ubuntu 24.04, BIND 9.18.39) · Fecha: 16/10/2026

Reglas que respeté (sección 7 de la guía):
- Nunca pegué el `secret` de la clave TSIG (`compartido/transferencia.key`) en la IA ni en un repositorio.
- Usé la sintaxis actual de BIND 9.18 (`primary`, `secondary`, `primaries`), no `master`/`slave`.
- Pedí la sintaxis de cada tipo de registro por separado y la comprobé con `named-checkzone`; no pedí las zonas
  completas.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Dónde estaba la carpeta `red_dns`. | La que tenía (de un compañero) era la del Lab 6: solo el nodo `cliente`, montaba `lab06` y arrancaba BIND sin systemd, por lo que `instalar_ns1.sh` fallaría en `systemctl`. Propuso una `red_dns` con los 4 nodos y systemd. | `docker compose ps`: ns1, ns2, resolutor y cliente en Up; `named -v` → 9.18.39. | Antes de usar un archivo ajeno hay que leerlo y ver si sirve para lo que pide la guía. |
| 2 | Por qué `docker compose` decía "no configuration file provided" y `/lab/lab07` estaba vacío. | Había carpetas repetidas (`red_dns\red_dns`, `lab07\lab07`); el compose monta la carpeta de arriba como `/lab`. | Moví los archivos un nivel; `ls /lab/lab07` mostró ns1, ns2 y los scripts. | Las rutas relativas del compose dependen de dónde está el archivo. |
| 3 | Por qué fallaban comandos como `Move-Item` y `cd $HOME\...`. | Los escribí dentro de ns1 (Linux); son de PowerShell. | Distinguí el prompt `PS C:\...>` de `root@ns1:/#`. | Cada terminal tiene su propio lenguaje de comandos. |
| 4 | Sintaxis de CNAME, MX, A, TXT/SPF y CAA. | `portal IN CNAME www`, `@ IN MX 10 mail`, `mail IN A …`, `@ IN TXT "v=spf1 mx -all"`, `@ IN CAA 0 issue "…"`. | `named-checkzone` → OK; verificador: CNAME, MX, SPF y CAA ✅. | Un nombre sin punto final se completa con `$ORIGIN`. |
| 5 | Por qué los PTR llevan punto final. | El `$ORIGIN` de la inversa es `10.10.10.in-addr.arpa.`; sin punto el nombre quedaría mal. | `dig -x 10.10.10.25 +short` → `mail.horizonte.internal.` | La IP se escribe al revés porque lo general va a la derecha. |
| 6 | Qué opciones de `named.conf` cambiar (recursión, versión, TSIG, NOTIFY). | `recursion no`, `version "no disponible"`, `allow-transfer { key … }`, `also-notify`, bloque `server … keys`. | Verificador 16 de 16; `google.com` → REFUSED; AXFR sin clave → Transfer failed; `version.bind` → "no disponible". | Un autoritativo no debe resolver nombres ajenos ni dejar copiar la zona. |
| 7 | Cómo interpretar `flags: qr aa rd` y el aviso "recursion requested but not available". | `aa` = respuesta autoritativa; falta `ra` porque no ofrece recursión. | Lo vi en las consultas a ns1 y ns2. | Diferencia entre servidor autoritativo y resolutor. |
| 8 | Qué significa la línea `TSIG hmac-sha256 …` del AXFR con clave. | Es la firma (MAC) de esa transferencia, no el secreto de la clave. | No la usé para nada más y no mostré el archivo `.key`. | La clave nunca viaja: solo viaja la firma. |
| 9 | El aviso `file does not end with newline`. | Faltaba un Enter después de la última línea de la zona; BIND lo tolera. | Agregué el salto de línea y volvió a cargar sin el aviso. | Leer también los avisos de BIND. |
| 10 | Cómo encontrar en el journal la transferencia. | `journalctl -u named --no-pager \| grep -E "notify\|Transfer\|transfer of"`. | Aparecieron `notify … serial 2026100702`, `TSIG transferencia-horizonte`, `Transfer completed` y, sin subir el serial, `zone is up to date`. | El NOTIFY avisa, pero el secundario solo copia si el serial es mayor. |

## Conclusión
La IA me ayudó a preparar el entorno (la carpeta `red_dns` correcta y las rutas), a entender la sintaxis de
cada registro y opción de BIND, y a interpretar los mensajes de `named-checkzone`, `dig` y `journalctl`. Todo se
comprobó en la red de laboratorio: 16 de 16 en el verificador y las transferencias firmadas con TSIG visibles en
el journal de ns2. El secreto de la clave TSIG nunca salió de los servidores.

## Defensa — Rol Sincronización (José María Orihuela)
Explico cómo ns2 copia la zona de ns1: la transferencia solo se permite con la clave TSIG
(sin clave sale "Transfer failed"). Cuando cambia la zona, ns1 envía un NOTIFY y ns2 copia
solo si el serial es mayor; si no se sube el serial, ns2 queda desactualizado.

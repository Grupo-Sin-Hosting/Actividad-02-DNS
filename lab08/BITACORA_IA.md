# Bitácora de uso de IA — Laboratorio 8 (Unbound, DoT, RPZ y DNSControl)

Estudiante: Lizeth Rodríguez · Entorno: red Docker `red_dns`, resolutor 10.10.10.4 (Ubuntu 24.04, Unbound 1.19.2,
DNSControl 5.2.0) · Fecha: 17–18/10/2026

Reglas que respeté (sección 7 de la guía):
- El resolutor **nunca** se abrió a cualquier IP: `access-control: 0.0.0.0/0 refuse` y solo se permiten
  `127.0.0.0/8` y `10.10.10.0/24` (verificador: ✅ Acceso solo para la red del colegio).
- La RPZ solo contiene los dominios de ejemplo de la guía. No cargué listas generadas por la IA.
- `creds.json` usa el proveedor `bind` local, sin tokens. Para Cloudflare el token iría en una variable de entorno
  (`$CLOUDFLARE_APITOKEN`), nunca en el repositorio.
- Pedí sintaxis e hipótesis, y cada respuesta la comprobé con `dig`, `tcpdump`, `unbound-checkconf`,
  `dnscontrol preview` o el verificador.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Por qué `sed` decía `can't read /lab/lab08/unbound/*`. | Al descomprimir quedó `lab08/lab08`; había que subir los archivos un nivel. | `ls /lab/lab08` mostró `unbound`, `dns-como-codigo` y los scripts. | Revisar la estructura de carpetas antes de ejecutar. |
| 2 | El instalador parecía colgado y no mostraba nada. | Ejecutarlo con `bash -x` para ver en qué línea estaba (podía ser `unbound-anchor` o la descarga de DNSControl). | `bash -x` mostró cada paso hasta `active`; `unbound -V` → 1.19.2 y `named` inactive. | `bash -x` sirve para depurar scripts. |
| 3 | Hipótesis para el SERVFAIL de `www.horizonte.internal` (prompt 1 de la guía). | (a) DNSSEC rechaza `.internal` por no existir en la raíz; (b) ns1/ns2 caídos; (c) el cambio no se instaló. Con un `dig` para cada una. | `dig @10.10.10.2` y `@10.10.10.3` → 10.10.10.20 (descarta b); `grep` del `.conf` instalado no tenía `domain-insecure` (confirma c). | Diagnosticar descartando hipótesis con evidencia. |
| 4 | Por qué mis cambios no aparecían en el archivo instalado. | VS Code tenía abierta la ruta vieja `lab08\lab08\…` y guardó allí, recreando la carpeta repetida. | `grep -c domain-insecure` → 0 en `/lab/lab08/unbound`; `find /lab/lab08/lab08` mostró el `.conf` con los cambios; se copió y se borró la carpeta. | Fijarse en la ruta de la pestaña de VS Code. |
| 5 | Diferencia entre `stub-zone` y `forward-zone` (prompt 2). | `stub-zone` pregunta directo a los autoritativos de una zona (ns1/ns2); `forward-zone` entrega la consulta a otro resolutor que hace la recursión (1.1.1.1/9.9.9.9). | `unbound-control lookup www.bbc.com` → "forwarding request" a 1.1.1.1 y 9.9.9.9; `www.horizonte.internal` → 10.10.10.20 vía ns1/ns2. | Cuándo usar cada una. |
| 6 | Sintaxis de DoT en Unbound. | `forward-tls-upstream: yes` y `forward-addr: IP@853#nombre`; el nombre permite verificar el certificado con `tls-cert-bundle`. | tcpdump: solo `1.1.1.1.853` y `9.9.9.9.853`, con el saludo TLS (320 B y ≈3 KB de certificado); antes se veía `A? www.wikipedia.org` por el 53. | Qué ve y qué no ve alguien en la red. |
| 7 | Cómo leer la salida de tcpdump con DoT. | `[S]`/`[S.]`/`[.]` = conexión TCP; los paquetes grandes del inicio son el certificado; luego solo hay tamaños cifrados. | Identifiqué cada fase en mi captura y la línea `SOA?` de ns2 → ns1 como tráfico interno. | Diferenciar tráfico interno del que sale a internet. |
| 8 | Por qué la RPZ podía fallar con mis líneas. | Empezaban con dos espacios; en un archivo de zona eso significa "mismo nombre que la línea anterior". | Las dejé en la columna 1; `grep -n` lo confirmó y las 4 pruebas dieron NXDOMAIN, 10.10.10.20 (×2) y NODATA, con `rpz: applied` en el journal. | El formato de zona es sensible a los espacios. |
| 9 | Por qué el verificador dio ❌ en caché (16/17). | Revisamos su función `cache`: consulta dos veces `www.upds.edu.bo` y exige ≤ 2 ms en la segunda. La primera había tardado por reabrir la sesión TLS. | Dos `dig` manuales → 8 ms y 0 ms; el verificador repetido → **17 de 17**. | Leer el script del verificador en vez de cambiar la configuración a ciegas. |
| 10 | Qué significaba `completed with errors` en `dnscontrol preview`. | No existía la carpeta `zonas`; `preview` no la crea. | `mkdir -p zonas` → `preview` limpio; `push` → `WRITING ZONEFILE (serial 2026101800)`, `named-checkzone` OK y luego `0 corrections`. | Distinguir un error del entorno de un error del código. |
| 11 | Ideas para la tabla de la Parte F (Windows Server y DNS gestionado). | Zonas integradas en AD y replicación de AD; DNS Policies; DNS gestionado con anycast y filtrado aparte. | Lo contrasté con la documentación de Microsoft Learn (particiones DomainDnsZones/ForestDnsZones, `Add-DnsServerQueryResolutionPolicy`), DNSControl y la política de NIC.bo. | Comparar con fuentes oficiales y no solo con lo que dice la IA. |

## Conclusión
La IA me sirvió sobre todo para diagnosticar: el SERVFAIL, el archivo que no se instalaba, la RPZ con espacios y el
❌ de caché. En cada caso la causa la confirmé con un comando (`dig`, `grep`, `tcpdump`, el propio verificador)
antes de cambiar algo. El resolutor quedó cerrado a la red del colegio, la RPZ solo tiene los dominios de la guía
y no hay credenciales reales en el repositorio. Resultado final: **17 de 17** y el cliente resolviendo nombres
internos, internet y el filtro sin `@`.

## Defensa — Rol Resolutor (Lizeth Rodríguez)
Explico el resolutor Unbound: solo acepta la red del colegio, valida DNSSEC (domain-insecure
para .internal), permite la inversa privada (nodefault), sale cifrado por DoT al puerto 853
y filtra con RPZ (apuestas → NXDOMAIN, phishing → 10.10.10.20). El cliente usa 10.10.10.4.

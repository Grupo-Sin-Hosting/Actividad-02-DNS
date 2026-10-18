# Laboratorio 8 — Hoja de trabajo: el resolutor del colegio (Unbound) y el DNS como código

Nombre: Lizeth Rodríguez   Fecha: 18/10/2026

Red `red_dns` del Laboratorio 7 (ns1 10.10.10.2 y ns2 10.10.10.3 con `verificar_lab07.sh` en 16/16), resolutor
10.10.10.4 y cliente 10.10.10.50. En el resolutor se apagó BIND (`systemctl disable --now named`) y se instaló
Unbound 1.19.2 con `unbound-anchor`, `dns-root-data`, `tcpdump` y `curl`. Carpeta de trabajo: `/lab/lab08`.

## Parte A — Autoritativo vs resolutor
**1. ¿Qué responde cada uno a `www.upds.edu.bo`?**

| Servidor | Respuesta | Banderas |
|---|---|---|
| `dig @10.10.10.2` (ns1, autoritativo) | `status: REFUSED`, sin respuesta; aviso `recursion requested but not available` | `qr rd` (sin `ra`) |
| `dig @10.10.10.4` (resolutor) | `status: NOERROR`, `www.upds.edu.bo. A 35.212.117.103` | `qr rd ra` |

ns1 solo responde por sus zonas (`horizonte.internal` y su inversa) y rechaza todo lo demás porque tiene
`recursion no`. El resolutor sí sale a buscar la respuesta por los clientes: la bandera `ra` (*recursion
available*) lo indica.

**2. ¿Por qué el colegio necesita LOS DOS tipos de servidor?**
Porque hacen trabajos distintos y no conviene mezclarlos. El **autoritativo** (ns1/ns2) es la fuente de la verdad
de los nombres del colegio y debe estar cerrado: sin recursión y sin transferencias a extraños. El **resolutor**
es el que usan las PCs: busca cualquier nombre de internet, guarda las respuestas en caché, valida DNSSEC, cifra
la salida y aplica la política del colegio (RPZ). Para los nombres internos el resolutor pregunta directamente a
ns1/ns2 con una `stub-zone`. Si un mismo servidor hiciera las dos cosas, un fallo o un ataque contra la
recursión afectaría también a la zona del colegio, y un autoritativo abierto a la recursión puede usarse para
ataques de amplificación.

## Parte B — Completa la configuración (10 TODO)
| Archivo | TODO | Qué se escribió | Qué aprendí |
|---|---|---|---|
| `unbound/horizonte-resolutor.conf` | 1 | `access-control: 0.0.0.0/0 refuse`, `127.0.0.0/8 allow`, `10.10.10.0/24 allow` | Un resolutor abierto al mundo sirve para ataques de amplificación; solo la red del colegio debe usarlo. |
| | 2 | `domain-insecure: "horizonte.internal"` y `domain-insecure: "10.10.10.in-addr.arpa"` | `.internal` no existe en la raíz firmada; sin esta excepción DNSSEC marca nuestras respuestas como falsas. |
| | 3 | `local-zone: "10.in-addr.arpa." nodefault` | Unbound bloquea por defecto las inversas privadas; `nodefault` deja pasar nuestra stub-zone. |
| | 4–5 | `forward-tls-upstream: yes`, `forward-addr: 1.1.1.1@853#cloudflare-dns.com`, `forward-addr: 9.9.9.9@853#dns.quad9.net` | DoT: la salida a internet va cifrada y el nombre después de `#` permite verificar el certificado del servidor. |
| `unbound/rpz.horizonte.internal` | 1 | `*.apuestas-ejemplo.com CNAME .` | El comodín cubre los subdominios; `CNAME .` = NXDOMAIN. |
| | 2 | `horizonte-notas-login.com A 10.10.10.20` y `*.horizonte-notas-login.com A 10.10.10.20` | Un registro `A` en la RPZ redirige el phishing a la página de aviso del colegio. |
| `dns-como-codigo/dnsconfig.js` | 1 | `SOA("@", "ns1.ue-horizonte.example.", "ti.ue-horizonte.example.", 3600, 600, 1209600, 300)` | Sin SOA explícito DNSControl escribe `default_not_set`. |
| | 2 | `DMARC_BUILDER({ policy: "quarantine", rua: ["mailto:dmarc@ue-horizonte.example"] })` | Genera el TXT `_dmarc` con la sintaxis correcta. |
| | 3 | `CAA_BUILDER({ label: "@", iodef: "mailto:ti@ue-horizonte.example", issue: ["letsencrypt.org"], issuewild: "none" })` | Solo Let's Encrypt emite; ningún comodín (`issuewild ";"`); avisos a TI. |

`bash /lab/lab08/instalar_resolutor.sh` → `unbound-checkconf: no errors` · `active` · `Resolutor listo`.
En `dns-como-codigo/`: `mkdir -p zonas && dnscontrol push` → `WRITING ZONEFILE … (serial 2026101800)`.
`bash /lab/lab08/verificar_lab08.sh` → **Resultado: 17 de 17 comprobaciones.**

Detalles que hubo que cuidar:
- Las líneas de la RPZ deben empezar en la columna 1. En un archivo de zona, una línea que empieza con espacio
  significa "mismo nombre que la línea anterior".
- Antes de instalar se normalizaron los fines de línea de Windows con `sed -i 's/\r$//'`.
- VS Code tenía abierta la ruta vieja `lab08\lab08\unbound\…` (carpeta repetida al descomprimir) y guardó allí el
  `.conf`. Por eso la primera reinstalación no tomó los cambios. Se copió el archivo a `/lab/lab08/unbound/`, se
  borró la carpeta repetida y se reabrieron los archivos desde la ruta correcta.

## Parte C — Experimentos
**1. Sin `domain-insecure`.** `dig @10.10.10.4 www.horizonte.internal` → **`status: SERVFAIL`** (780 ms la primera
vez, 4 ms la segunda porque el fallo también queda en caché). Unbound valida DNSSEC desde la raíz. La raíz está
firmada y responde, con prueba criptográfica, que el TLD `.internal` **no existe**. Cuando ns1 dice lo contrario,
la respuesta no encaja en la cadena de confianza y el validador la considera *bogus* (falsificada). Así que la
rechaza, igual que haría con un ataque. `domain-insecure` le dice: "esta zona no está firmada; no la valides".
Con eso: **`NOERROR` → `10.10.10.20`**.

**2. Sin `local-zone: "10.in-addr.arpa." nodefault`.** `dig @10.10.10.4 -x 10.10.10.25 +short` → **vacío**.
Unbound trae zonas locales por defecto para las inversas de las redes privadas (RFC 1918), del tipo `static`.
Responde él mismo "no existe" sin preguntar a nadie, para no filtrar a internet consultas sobre IPs internas. Por
eso la stub-zone `10.10.10.in-addr.arpa` nunca se consultaba. Con `nodefault` se quita esa zona y la consulta va
a ns1/ns2: **`mail.horizonte.internal.`**

**3. Caché.**

| Consulta | 1.ª vez | 2.ª vez | TTL |
|---|---|---|---|
| `www.mit.edu` (dominio nuevo) | **844 ms** | **0 ms** | 60 → 55 |
| `www.bbc.com` (ya estaba en caché) | 0 ms | 0 ms | 57 → 52 |
| `www.bcb.gob.bo` (el de la guía) | 0 ms | 0 ms | — (ya estaba en caché por pruebas previas) |

La primera consulta de un nombre nuevo recorre DoT hasta Cloudflare/Quad9 y valida firmas. La segunda sale de la
memoria del resolutor en 0 ms, y el TTL va bajando porque la caché descuenta el tiempo transcurrido.
`unbound-control stats_noreset` mostraba **13 consultas: 8 desde la caché y 5 hacia afuera**.
`unbound-control lookup www.bbc.com` confirma que se reenvía a 1.1.1.1 y 9.9.9.9.

**4. DNSSEC.**
- `dig +dnssec @10.10.10.4 cloudflare.com` → `NOERROR` y **`flags: qr rd ra ad`**. `ad` (*Authenticated Data*)
  significa que Unbound verificó la cadena de firmas desde la raíz hasta cloudflare.com; `do` indica que se
  pidieron las firmas.
- `dig @10.10.10.4 dnssec-failed.org` → **`SERVFAIL`**. Las firmas de ese dominio están rotas a propósito y el
  resolutor prefiere no responder antes que entregar una respuesta que podría estar falsificada.
- `dig @10.10.10.4 dnssec-failed.org +cd +short` → `96.99.227.255`. Con *checking disabled* sí hay respuesta,
  lo que demuestra que el SERVFAIL lo causa la validación y no la red.

## Parte D — ¿Sale cifrado?
| Configuración | Lo que mostró `tcpdump -ni eth0 -l port 53 or port 853` | Conclusión |
|---|---|---|
| **Sin DoT** (`forward-addr: 1.1.1.1`) | `10.10.10.4.44767 > 1.1.1.1.53: … A? www.wikipedia.org.` y la respuesta `CNAME dyna.wikimedia.org., A 195.200.68.224` | Sale por **UDP 53, en texto plano**: cualquiera en el camino (el proveedor) ve el nombre consultado y la respuesta. |
| **Con DoT** (`forward-tls-upstream: yes`) | `10.10.10.4.46380 > 1.1.1.1.853: Flags [S]`, `[S.]`, `[.]` (conexión TCP), `length 320` (ClientHello) y `length 1420 + 1420 + 40` (certificado). Luego paquetes de 80 a 942 bytes; también `10.10.10.4.42374 > 9.9.9.9.853`. **Ninguna línea `.53` hacia internet.** | Sale por **TCP 853 con TLS** hacia 1.1.1.1 y 9.9.9.9. Solo se ven tamaños, no nombres: el proveedor ya no sabe qué sitios consulta el colegio. |

En la captura con DoT apareció también `10.10.10.3 > 10.10.10.2.53: SOA? horizonte.internal`. Es ns2 revisando el
serial de ns1 (el *refresh* del Lab 7): tráfico interno del aula, no sale a internet.

La primera consulta después de activar DoT dio `communications error … timed out`. Montar la sesión TLS por
primera vez tardó más que la espera de `dig`; el reintento respondió en 4 ms.

El comando exacto de la guía (`timeout 6 tcpdump … '(dst port 53 or dst port 853) and not dst net 10.10.10.0/24' &`)
se ejecutó, pero el `dig` se escribió cuando los 6 segundos ya habían terminado (`0 packets captured`). La
comprobación equivalente la hace el verificador (`solo_dot`, mismo filtro): **✅ Salida a internet solo cifrada
(DoT :853, nada por :53)**.

## Parte E — La zona pública como código
**1. Diff de `dnscontrol preview` al cambiar `IP_WEB` a `203.0.113.21`:**
```
2 corrections (bind)
#1: ± MODIFY ue-horizonte.example A (203.0.113.20 ttl=3600) -> (203.0.113.21 ttl=3600)
± MODIFY www.ue-horizonte.example A (203.0.113.20 ttl=3600) -> (203.0.113.21 ttl=3600)
Done. 2 corrections.
```
No se hizo `push`. Se devolvió el valor original y `preview` volvió a `0 corrections`.

**¿Por qué es mejor que editar el archivo de zona a mano?**
- **Se ve el cambio antes de aplicarlo.** `preview` muestra exactamente qué registros se crean, modifican o
  borran, como un `git diff`. Aquí se vio que cambiar una variable afecta a dos registros (`@` y `www`).
- **Una sola fuente de verdad.** La IP está en una variable; no hay que buscarla en varias líneas ni arriesgarse a
  cambiar una y olvidar otra.
- **Validación y serial automáticos.** `dnscontrol check` detecta errores antes de publicar. El serial lo genera
  solo (`2026101800`), así no se repite el error del Lab 7 de olvidar subirlo. La zona generada pasó
  `named-checkzone` → `OK`.
- **Idempotente y versionable.** Si nada cambió, `preview` da `0 corrections`. El archivo `.js` se guarda en Git,
  se revisa en un *pull request* y queda historial de quién cambió qué.
- **Los *builders* evitan errores de sintaxis.** `DMARC_BUILDER` y `CAA_BUILDER` generaron
  `v=DMARC1; p=quarantine; rua=…` y los tres CAA (`issue`, `issuewild ";"`, `iodef`) sin escribirlos a mano.

**2. ¿Qué habría que cambiar en `creds.json` para publicar en Cloudflare?**
Agregar un proveedor de tipo `CLOUDFLAREAPI` cuyo token se lea de una **variable de entorno**, nunca escrito en
el archivo:
```json
{
  "cloudflare": { "TYPE": "CLOUDFLAREAPI", "apitoken": "$CLOUDFLARE_APITOKEN" },
  "none": { "TYPE": "NONE" }
}
```
En `dnsconfig.js`, cambiar `NewDnsProvider("bind")` por `NewDnsProvider("cloudflare")`. Antes de `dnscontrol
push` se exporta el token (`export CLOUDFLARE_APITOKEN=…`) con permiso solo de *Zone:DNS:Edit* para esa zona.
DNSControl reemplaza los valores que empiezan con `$` por la variable de entorno, así que `creds.json` puede ir
al repositorio sin secretos (y si hubiera uno real, debe estar en `.gitignore`, como `creds.reales.json`).

## Parte F — Comparación
| Tema | BIND/Unbound en Linux (este curso) | DNS de Windows Server / Active Directory | DNS gestionado (Cloudflare, NIC.bo) |
|---|---|---|---|
| Dónde se guardan las zonas | Archivos de texto: `db.horizonte.internal` en ns1, copias en `/var/lib/bind/` en ns2; la RPZ en `/etc/unbound/`; la zona pública generada en `zonas/` desde `dnsconfig.js`. | Integradas en Active Directory (particiones `DomainDnsZones` o `ForestDnsZones`), o como archivos `.dns` en `%SystemRoot%\System32\dns` si son zonas estándar. | En la infraestructura del proveedor; se editan por panel web o API (DNSControl con `CLOUDFLAREAPI`). NIC.bo registra el dominio `.bo` y delega a los servidores DNS que indique el titular. |
| Cómo se replican | Primario → secundario con AXFR/IXFR, firmadas con TSIG y avisadas con NOTIFY; el secundario solo copia si el serial sube. | Replicación de Active Directory entre controladores de dominio (multimaestro: se puede editar en cualquiera); también admite transferencias de zona clásicas a secundarios. | El proveedor la distribuye en su red *anycast* mundial; el cliente no administra secundarios. |
| Filtrado (RPZ / directivas) | RPZ estándar en Unbound: `CNAME .` (NXDOMAIN), `CNAME *.` (NODATA), `A` (redirigir), con registro en el journal (`rpz: applied`). | Directivas DNS (DNS Policies, desde Windows Server 2016) con `Add-DnsServerQueryResolutionPolicy -Action IGNORE` para bloquear dominios; no usa el formato RPZ. | El DNS autoritativo no filtra. El filtrado es un servicio aparte del resolutor: 1.1.1.1 for Families (1.1.1.2 / 1.1.1.3) o Cloudflare Gateway (Zero Trust) con listas por categorías. |
| Costo y quién lo mantiene | Software libre sin licencia; lo mantiene el equipo de TI del colegio (configuración, parches, monitoreo, respaldos). | Licencia de Windows Server y CAL; lo mantiene TI, normalmente junto con el dominio AD (usuarios y equipos). | Plan gratuito o de pago por suscripción; la disponibilidad la mantiene el proveedor y el colegio solo administra los registros. El dominio `.bo` paga registro y renovación anual a NIC.bo. |

**Conclusión de la comparación:** para el colegio tiene sentido una combinación. La zona **pública**
(`ue-horizonte.example`) iría en un DNS gestionado, administrada con DNSControl desde Git. La resolución
**interna** y el filtrado van en el resolutor propio, porque solo así se controla la caché, la política RPZ y la
privacidad de lo que consultan los alumnos.

## Reflexión
**¿Qué ventajas de privacidad y seguridad gana el colegio con su propio resolutor frente a usar el DNS del
proveedor?**

1. **Privacidad.** Con el DNS del proveedor, este ve cada sitio que visita cada computadora del colegio. Con el
   resolutor propio, las consultas salen **cifradas por DoT** (puerto 853, demostrado con tcpdump) y con
   `qname-minimisation`. El proveedor de internet solo ve conexiones TLS hacia 1.1.1.1 y 9.9.9.9, sin nombres.
2. **Protección contra phishing y contenido no deseado.** La RPZ redirige `horizonte-notas-login.com`, el enlace
   del correo falso que llegó a los padres, a la página de aviso del colegio (`10.10.10.20`). También bloquea las
   apuestas con todos sus subdominios y deja sin datos a los rastreadores. Cada acción queda registrada
   (`rpz: applied [filtro-colegio]`), lo que permite ver quién intentó entrar.
3. **Respuestas verificadas.** La validación DNSSEC (bandera `ad`) rechaza respuestas falsificadas, como en
   `dnssec-failed.org` → SERVFAIL, y protege de envenenamiento de caché. `private-address` evita ataques de
   *DNS rebinding*.
4. **Nombres internos.** Las PCs resuelven `horizonte.internal` y su inversa sin depender de archivos `hosts`,
   gracias a las stub-zones hacia ns1/ns2.
5. **Velocidad y continuidad.** La caché responde en 0 ms lo ya consultado. `serve-expired` sigue respondiendo
   lo último conocido (hasta un día) si se cae internet.
6. **No es un arma para otros.** `access-control` solo admite `127.0.0.0/8` y `10.10.10.0/24`. Un resolutor
   abierto podría usarse para ataques de amplificación. Además, `hide-version` no revela qué software corre.

El costo es que el colegio pasa a ser responsable de mantenerlo (actualizaciones, monitoreo y la propia lista
RPZ), y si el resolutor se cae, se cae el DNS de todas las PCs. Por eso conviene tener al menos dos resolutores,
como se hizo con ns1 y ns2.

# Laboratorio 6 — Hoja de trabajo: radiografía DNS de dominios reales

Nombre: Lizeth Rodríguez   Fecha: 14/10/2026

Entorno: servidor Ubuntu 24.04 en Docker (`horizonte-servidor-lab02`), DiG 9.18.39. Todas las consultas con el
resolutor explícito `@1.1.1.1`, porque el resolutor interno de Docker (127.0.0.11) no sirve para `+trace`.

## Parte A — El viaje de una consulta
`dig +trace +nodnssec @1.1.1.1 www.upds.edu.bo`

**1. Saltos, quién respondió y cuánto tardó**

| Salto | Quién respondió | Tiempo | Qué entregó |
|---|---|---|---|
| 1 | `1.1.1.1` (resolutor recursivo de Cloudflare) | 120 ms | La lista de los 13 servidores raíz (a…m.root-servers.net) |
| 2 | `m.root-servers.net` (202.12.27.33) — raíz | 172 ms | Referencia a los NS de `.bo`: ns.nic.bo, anycast.ns.nic.bo, ns2.nic.fr, ns.dns.br |
| 3 | `ns.nic.bo` (166.114.1.40) — TLD .bo | 108 ms | Referencia (delegación) a los NS de `upds.edu.bo`: ns2…ns6.megalink.com |
| 4 | `ns5.megalink.com` (88.99.13.51) — autoritativo | 331 ms | La respuesta final: `www.upds.edu.bo. 300 IN A 35.212.117.103` |

Fueron **4 saltos**: resolutor → raíz → `.bo` → autoritativo de `upds.edu.bo`. Cada paso intermedio no da la
respuesta sino una **referencia** ("pregunta a estos otros"), hasta llegar al servidor que tiene la zona. En la
traza respondió `m.root`; en la clase fue `i.root`: cualquiera de las 13 raíces sirve, y `dig` elige una.

**2. ¿Quién administra cada zona?**
- `.bo`: **NIC Bolivia** (`ns.nic.bo`, `anycast.ns.nic.bo`), con servidores secundarios en el extranjero
  (`ns2.nic.fr` de Francia y `ns.dns.br` de Brasil) para tener redundancia. `edu.bo` no tiene servidores
  propios: es parte de la zona `.bo`.
- `upds.edu.bo`: el proveedor **Megalink** (`ns2…ns6.megalink.com`).

**3. NS de la delegación vs NS de la zona**

| Delegación (lo que dice `.bo`, TTL 17600) | Zona (`dig +short upds.edu.bo NS`, TTL 86400) |
|---|---|
| ns2, ns3, ns4, ns5, **ns6**.megalink.com | ns2, ns3, ns4, ns5.megalink.com |

**No coinciden**: el padre (`.bo`) todavía delega en `ns6.megalink.com`, pero la propia zona ya no lo declara.
Si un resolutor elige ns6 y este no responde con autoridad, la consulta falla o se demora hasta probar otro
servidor. Es una **delegación coja** (lame delegation), que el script de la Parte D detecta.

## Parte B — Tipos de registro
| Consulta | Resultado | ¿Para qué sirve este registro? |
|---|---|---|
| `dig +short upds.edu.bo A` | `35.212.117.103` | **A**: traduce el nombre a una dirección **IPv4**. |
| `dig +short upds.edu.bo AAAA` | *(vacío)* | **AAAA**: nombre → dirección **IPv6**. upds.edu.bo **no tiene IPv6**. |
| `dig +short upds.edu.bo MX` | `0 upds-edu-bo.mail.protection.outlook.com.` | **MX**: a qué servidor se entrega el correo del dominio; el número es la prioridad (menor = preferido). El correo de la UPDS lo recibe **Microsoft 365**. |
| `dig +short upds.edu.bo TXT` | `"v=spf1 include:spf.protection.outlook.com -all"`, `"MS=ms99859365"`, `"MS=ms26917543"`, `"google-site-verification=…"` | **TXT**: texto libre. Aquí: el **SPF** (solo los servidores de Outlook pueden enviar correo como @upds.edu.bo; `-all` rechaza al resto) y códigos que prueban a Microsoft y Google que la UPDS es dueña del dominio. |
| `dig +short _dmarc.upds.edu.bo TXT` | `"v=DMARC1; p=quarantine; sp=quarantine; rua=mailto:abuse@megalink.com; ruf=…; pct=100; ri=86400; aspf=s; fo=1:s"` | **DMARC**: qué hacer con un correo que dice ser de @upds.edu.bo pero falla SPF/DKIM. `p=quarantine` → enviarlo a spam; `sp` lo aplica a subdominios; `pct=100` a todos los correos; `rua`/`ruf` dónde mandar los reportes; `aspf=s` alineación estricta. |
| `dig upds.edu.bo SOA +noall +answer` | `upds.edu.bo. 86400 IN SOA NS2.MegaLink.com. <usuario>.megalink.com.upds.edu.bo. 2026081101 28800 7200 1209600 7200` | **SOA** (inicio de autoridad), explicado abajo. |
| `dig +short -x 35.212.117.103` | `103.117.212.35.bc.googleusercontent.com.` | **PTR**: la resolución inversa, IP → nombre. Muestra que el sitio está alojado en **Google Cloud**. Es clave para el correo (los servidores verifican el PTR del remitente). |
| `dig +short cloudflare.com HTTPS` | `1 . alpn="h3,h2" ipv4hint=104.16.132.229,104.16.133.229 ipv6hint=2606:4700::6810:84e5,2606:4700::6810:85e5` | **HTTPS (SVCB)**: le dice al navegador, antes de conectar, que el sitio admite **HTTP/3** (`h3`) y HTTP/2, y le da las IP. Así ahorra un viaje. |
| `dig +short google.com CAA` | `0 issue "pki.goog"` | **CAA**: qué autoridades certificadoras pueden emitir certificados para el dominio. Solo la CA de Google (`pki.goog`) puede emitir para google.com. |

**Cada número del SOA de upds.edu.bo**

| Campo | Valor | Significado |
|---|---|---|
| MNAME | `NS2.MegaLink.com.` | Servidor primario de la zona. |
| RNAME | `<usuario>.megalink.com.upds.edu.bo.` | Correo del responsable, con `.` en lugar de `@`. |
| Serial | `2026081101` | Versión de la zona en formato AAAAMMDDnn: 11/08/2026, cambio n.º 01. Debe subir en cada cambio o los secundarios no se actualizan. |
| Refresh | `28800` | Cada 8 h los secundarios preguntan al primario si hay un serial nuevo. |
| Retry | `7200` | Si el primario no responde, reintentan cada 2 h. |
| Expire | `1209600` | Si pasan 14 días sin contactar al primario, el secundario deja de responder por la zona. |
| TTL negativo | `7200` | Durante 2 h se recuerda en caché que un nombre **no existe** (NXDOMAIN). |
| TTL del registro | `86400` | El propio SOA se puede guardar en caché 1 día. |

**El problema del RNAME**: debería ser `<usuario>.megalink.com.` (correo `<usuario>@megalink.com`), pero
termina en `.megalink.com.upds.edu.bo.`. En el archivo de zona se escribió sin el **punto final**, y un nombre sin
punto final se considera relativo: BIND le agrega el origen de la zona (`upds.edu.bo.`). Es el error n.º 1 de
BIND. No rompe la resolución, pero el correo del responsable queda inválido.

## Parte C — TTL y caché
`dig @1.1.1.1 www.upds.edu.bo A +noall +answer` dos veces con 5 segundos de diferencia:

```
www.upds.edu.bo.        300     IN      A       35.212.117.103
www.upds.edu.bo.        300     IN      A       35.212.117.103
```

**¿Qué pasó con la segunda columna?** Es el **TTL**: cuántos segundos más se puede guardar la respuesta en
caché. En este primer intento las dos consultas dieron **300**, el TTL completo que publica el autoritativo
(lo confirma la traza de la Parte A: `www.upds.edu.bo. 300 IN A`). La explicación es que `1.1.1.1` es un servicio
**anycast**: muchos servidores en el mundo, cada uno con su propia caché. Ninguno tenía el registro guardado,
así que cada uno consultó al autoritativo y entregó el TTL entero.

Repetí la consulta 4 veces seguidas, cada 5 segundos:

```
www.upds.edu.bo.        290     IN      A       35.212.117.103
www.upds.edu.bo.        285     IN      A       35.212.117.103
www.upds.edu.bo.        279     IN      A       35.212.117.103
www.upds.edu.bo.        274     IN      A       35.212.117.103
```

Ahora la respuesta sale de la **caché** del resolutor y el TTL **baja unos 5 segundos en cada consulta**
(290 → 285 → 279 → 274). El resolutor descuenta el tiempo que lleva guardada la respuesta; la diferencia de
6 s entre 285 y 279 se debe a lo que tarda el propio `dig` más el `sleep 5`. Cuando llegue a 0, el resolutor la
borra y vuelve a preguntar al autoritativo, que entrega de nuevo 300.

**Si cambio la IP de un sitio con TTL 86400**, los resolutores que ya tenían la IP vieja la seguirán usando
hasta que venza su caché: **hasta 24 horas**. No existe "la propagación DNS": son cachés que vencen.
Procedimiento profesional para migrar: (1) bajar el TTL a 300 un día antes, (2) cambiar la IP, (3) comprobar
y volver a subir el TTL.

## Parte D — Completa `radiografia_dns.sh`
Completé los 4 TODO:

1. **Delegación coja**: para cada NS (de la zona y del padre) se pide el SOA con `+norec`. Si la respuesta
   trae la bandera `aa` (*authoritative answer*), se guarda su serial (7.º campo de la línea SOA, con `awk`);
   si no, el servidor se anota en `COJOS`.
2. **DMARC**: se consulta el TXT de `_dmarc.<dominio>`, se toma la línea `v=DMARC1` y la política con
   `grep -o 'p=[a-z]*' | head -1` (el `head -1` evita confundir `p=` con `sp=`, la política de subdominios).
   Sin registro → ❌; `p=none` → ⚠️ (solo observa); `quarantine`/`reject` → ✅.
3. **CAA**: con registros → ✅; sin registros → ❌ (cualquier CA puede emitir certificados para el dominio).
4. **DNSSEC**: se busca el registro **DS** (vive en la zona del padre) y se pide el SOA con `+dnssec` para ver
   si el resolutor puso la bandera `ad` (*authenticated data*: validó las firmas). DS + `ad` → ✅;
   DS sin `ad` → ❌ (validación rota); sin DS → ❌ (no firmado).

**Resultado: `bash verificar_lab06.sh` → 12 de 12 comprobaciones.**

| Dominio | Puntaje | Hallazgos |
|---|---|---|
| cloudflare.com | **12 de 12** | 5 NS coherentes; IPv4 e IPv6; SPF `-all`; DMARC `p=reject`; CAA con 5 CA autorizadas y `iodef` para avisos; DNSSEC firmado y validado (DS en `.com`, flag `ad`). |
| upds.edu.bo | **6 de 12** | ⚠️ `.bo` delega en ns6 pero la zona no lo declara; ❌ ns6 no responde con autoridad (delegación coja); ⚠️ RNAME sin punto final; ⚠️ sin IPv6; ✅ SPF `-all` y DMARC `p=quarantine`; ❌ sin CAA; ❌ sin DNSSEC. |

> **Problema encontrado:** en una ejecución las consultas no alcanzaron respuesta a tiempo (`;; no servers
> could be reached`) y el script mostró ✅ falsos (por ejemplo "la delegación coincide") porque comparó
> valores vacíos. El verificador, en su propia ejecución, sí dio 12/12, y al repetir la radiografía salió el
> resultado correcto. Lección: un diagnóstico DNS depende de que la red responda; si aparece un error de `dig`
> en la salida, hay que repetir la consulta antes de sacar conclusiones.

**Recomendaciones para upds.edu.bo** (como consultora, con datos públicos):
1. Pedir a NIC Bolivia que **quite `ns6.megalink.com` de la delegación** (o volver a configurarlo como
   autoritativo): hoy algunos resolutores pierden tiempo preguntando a un servidor que no responde.
2. **Corregir el RNAME del SOA** agregando el punto final (`<usuario>.megalink.com.`) y subir el serial.
3. Agregar **CAA** (por ejemplo `0 issue "letsencrypt.org"` o la CA que usen) y evaluar **DNSSEC**;
   también publicar **AAAA** si el hosting ofrece IPv6. Como siguiente paso del correo, pasar DMARC de
   `quarantine` a `reject`.

## Parte E — Tu propio análisis
Analicé dos dominios bolivianos públicos: un banco y un periódico. Son datos públicos del DNS, revisados con
`radiografia_dns.sh` el 14/10/2026 y comentados con respeto, como lo haría una consultora.

| Dominio | Puntaje | Lo que está bien | Lo que falla |
|---|---|---|---|
| **bnb.com.bo** (Banco Nacional de Bolivia) | **6 de 12** | DNS en Azure (5 NS); `www` → 45.5.13.100; correo en Microsoft 365; SPF estricto `-all`; DMARC `p=quarantine` | ⚠️ la delegación de `.bo` y los NS de la zona no coinciden; ❌ `ns.bnb.com.bo` y `ns1-02.azure-dns.com` no responden con autoridad; ⚠️ el dominio raíz no tiene A; ⚠️ sin IPv6; ❌ sin CAA; ❌ sin DNSSEC |
| **eldeber.com.bo** (periódico El Deber) | **9 de 12** | DNS en Cloudflare (2 NS coherentes); IPv4 e IPv6; correo protegido por Sophos; DMARC `p=reject` | ⚠️ SPF con `~all` (softfail) en vez de `-all`; ❌ sin CAA; ❌ sin DNSSEC |

**Recomendaciones para bnb.com.bo**
1. **Alinear la delegación con la zona.** `.bo` delega en `ns1-02.azure-dns.com`, pero la zona declara
   `ns.bnb.com.bo`, y ninguno de los dos responde con autoridad. Parece una migración a Azure DNS que no se
   terminó: hay que dejar en NIC Bolivia y en el registro NS de la zona exactamente los 4 servidores Azure
   asignados, y quitar `ns.bnb.com.bo`. Así ningún resolutor pierde tiempo con servidores cojos.
2. **Publicar un registro A en el dominio raíz** (o una redirección), para que quien escriba `bnb.com.bo`
   sin `www` llegue al sitio. Si el hosting lo permite, agregar también IPv6.
3. **Agregar CAA y DNSSEC.** Para un banco, limitar qué CA puede emitir certificados y firmar las respuestas
   DNS reduce el riesgo de suplantación del sitio. Después, pasar DMARC de `quarantine` a `reject`.

**Recomendaciones para eldeber.com.bo**
1. **SPF de `~all` a `-all`.** Con `~all` el correo falso solo se marca como sospechoso; con `-all` se rechaza.
   Como DMARC ya está en `reject`, el cambio solo hace más coherente la política.
2. **Activar DNSSEC.** Cloudflare lo ofrece con un clic; falta registrar el DS en NIC Bolivia.
3. **Agregar CAA** con la CA que usa Cloudflare para sus certificados, para que ninguna otra pueda emitir
   certificados para el periódico.

**Comparación:** ningún dominio boliviano analizado (upds.edu.bo, bnb.com.bo, eldeber.com.bo) tiene **CAA** ni
**DNSSEC**, mientras que cloudflare.com tiene ambos. Son las dos mejoras más comunes pendientes en el `.bo`.

## Reflexión
El DNS es la "guía telefónica" de internet porque traduce los nombres que recordamos (`www.upds.edu.bo`) en
las direcciones que usan las máquinas (`35.212.117.103`). Casi todos los servicios de un dominio dependen de
él al mismo tiempo:
- el **sitio web** necesita los registros A/AAAA;
- el **correo** necesita MX para recibir, y SPF/DMARC para que sus mensajes no se marquen como falsos;
- los **certificados** HTTPS se validan consultando el DNS (la CA comprueba el dominio y respeta el CAA).

Por eso un solo error —una delegación que apunta a un servidor que no responde, un serial que no se subió,
un nombre sin punto final o un TTL mal elegido— puede tumbar a la vez el sitio, el correo y la renovación de
certificados. Además, como las respuestas quedan en caché, el error (y su corrección) tarda en desaparecer.


## Defensa — Rol Diagnóstico (Juniors Parapaino)

En el Laboratorio 6 realizamos una radiografía DNS de dominios reales utilizando herramientas de diagnóstico como `dig`, `dig +trace` y consultas a servidores DNS.

Durante el análisis del dominio `upds.edu.bo`, identificamos dos problemas importantes:

1. **Delegación coja:** el servidor `ns6` no responde con autoridad para la zona correspondiente.
2. **Error en el registro SOA:** el campo RNAME del responsable presenta un problema relacionado con el punto final del nombre de dominio.

También aprendimos a verificar configuraciones DNS antes de aplicarlas utilizando:

- `named-checkconf`: comprueba la sintaxis de la configuración de BIND9.
- `named-checkzone`: verifica la estructura y validez de una zona DNS.

**Conclusión:** Este laboratorio nos permitió identificar problemas de delegación y configuración DNS, comprender la importancia de los servidores autoritativos y validar nuestras configuraciones antes de ponerlas en funcionamiento.

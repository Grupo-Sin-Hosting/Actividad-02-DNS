# Laboratorio 7 — Hoja de trabajo: el DNS autoritativo del colegio con BIND9

Nombre: Lizeth Rodríguez   Fecha: 16/10/2026

## Preparación: la red DNS del laboratorio
La carpeta `red_dns/` (Ubuntu 24.04 con systemd y BIND 9.18.39) está junto a `lab07/` y levanta 4 nodos en la
red `10.10.10.0/24`: **ns1 10.10.10.2** (primario), **ns2 10.10.10.3** (secundario), **resolutor 10.10.10.4**
(clase 8) y **cliente 10.10.10.50**. La carpeta de trabajo se monta en cada nodo como `/lab`.

```
cd red_dns
docker compose up -d --build
docker compose exec ns1 bash          # dentro: /lab/lab07
```

Problemas resueltos al preparar la red: la carpeta `red_dns` que circulaba era la del Lab 6 (solo tenía el nodo
`cliente`, montaba `lab06` y arrancaba BIND sin systemd), así que se usó una versión con los 4 nodos y systemd
para que funcionen `systemctl`, `rndc` y `journalctl -u named`. Además, al descomprimir quedaron carpetas
repetidas (`red_dns\red_dns`, `lab07\lab07`): como el compose monta la carpeta de arriba como `/lab`, hubo que
subir los archivos un nivel para que existiera `/lab/lab07/ns1/...`.

## Parte A — Completa las zonas (ns1)
- `ns1/db.horizonte.internal`: `portal IN CNAME www`; `@ IN MX 10 mail`, `mail IN A 10.10.10.25`,
  `@ IN TXT "v=spf1 mx -all"`; `@ IN CAA 0 issue "horizonte.internal"`.
- `ns1/db.10.10.10`: `20 IN PTR www.horizonte.internal.` y `25 IN PTR mail.horizonte.internal.`

`named-checkzone` cargó ambas zonas con el serial `2026100701` y terminó en **OK**.

**1. ¿Por qué los nombres de la derecha en la zona inversa llevan punto final?**
Porque en la zona inversa el `$ORIGIN` es `10.10.10.in-addr.arpa.`. Un nombre sin punto final se considera
relativo y BIND le agrega el origen: `www.horizonte.internal` se convertiría en
`www.horizonte.internal.10.10.10.in-addr.arpa.`, un nombre que no existe. Con el punto final el nombre es
completo (FQDN). A la izquierda, en cambio, va solo el último octeto (`20`, `25`), que sí se completa con el
origen: `20.10.10.10.in-addr.arpa.` La IP se escribe al revés porque en el DNS lo más general va a la derecha
(`arpa` → `in-addr` → `10` → `10` → `10`), igual que en `www.horizonte.internal`.

**2. ¿Qué pasa si escribes `mail.horizonte.internal` sin punto en el MX?**
En una copia de la zona (`/tmp/prueba`) se cambió el MX a `10 mail.horizonte.internal` y `named-checkzone`
mostró el aviso `MX 'mail.horizonte.internal.horizonte.internal' has no address records (A or AAAA)` **pero
igual terminó en OK**. Es decir, la zona carga, pero el MX apunta a un nombre inexistente y el correo del colegio
no llegaría. Lección: hay que leer los avisos de `named-checkzone`, no solo el OK. Lo correcto es `mail` (relativo)
o `mail.horizonte.internal.` (con punto final).

## Parte B — Configuración de BIND (ns1 y ns2)
- `ns1/named.conf.options`: `recursion no;` (un autoritativo solo responde por sus zonas; si resolviera nombres
  ajenos podría usarse en ataques de amplificación) y `version "no disponible";` (no revelar la versión a un
  atacante).
- `ns1/named.conf.local`, zona `horizonte.internal`: `allow-transfer { key "transferencia-horizonte"; };` (solo
  quien tenga la clave TSIG puede copiar la zona) y `also-notify { 10.10.10.3; };` (avisar a ns2 en cuanto cambie
  el serial).
- `ns2/named.conf.local`: `server 10.10.10.2 { keys { "transferencia-horizonte"; }; };` (todo lo que ns2 pide a
  ns1 va firmado con la clave) y la zona `10.10.10.in-addr.arpa` como `type secondary` con
  `primaries { 10.10.10.2; }` y archivo `/var/lib/bind/db.10.10.10.sec`.

Se usó la sintaxis actual de BIND 9.18 (`primary` / `secondary` / `primaries`), no la antigua `master` / `slave`.

Instalación: `bash /lab/lab07/instalar_ns1.sh` → `server reload successful` · `ns1 listo`;
`bash /lab/lab07/instalar_ns2.sh` → `type: secondary`, `serial: 2026100701`, `ns2 listo`.

Verificación desde el cliente: `docker compose exec cliente bash /lab/lab07/verificar_lab07.sh` →
**Resultado: 16 de 16 comprobaciones.**

## Parte C — Consultas desde el cliente
| Comando | Resultado | ¿Qué demuestra? |
|---|---|---|
| `dig @10.10.10.2 www.horizonte.internal` (mira `flags`) | `status: NOERROR`, `flags: qr aa rd`, `www.horizonte.internal. 3600 IN A 10.10.10.20`; aviso `recursion requested but not available` | La bandera **`aa`** (*authoritative answer*) indica que ns1 es dueño de la zona y responde con autoridad. Falta `ra`: no ofrece recursión. |
| `dig @10.10.10.3 portal.horizonte.internal` | `flags: qr aa rd`; `portal … CNAME www.horizonte.internal.` y `www … A 10.10.10.20` | **ns2** también responde con autoridad: la zona se copió. El CNAME funciona y el servidor entrega en la misma respuesta el A de destino. |
| `dig @10.10.10.2 -x 10.10.10.25 +short` | `mail.horizonte.internal.` | La zona inversa resuelve IP → nombre (PTR). Es clave para el correo: los servidores verifican que la IP del remitente tenga un PTR coherente. |
| `dig @10.10.10.2 google.com` | `status: REFUSED`, sin `aa` ni `ra` | ns1 **no hace recursión**: no busca nombres ajenos (`recursion no`). Resolver google.com es tarea del resolutor (clase 8). |
| `dig @10.10.10.2 horizonte.internal AXFR` | `; Transfer failed.` | Sin la clave TSIG nadie puede copiar la zona completa. Así un atacante no puede obtener la lista de todos los equipos del colegio. |
| `dig -k …/transferencia.key @10.10.10.2 horizonte.internal AXFR` | La zona completa: SOA, TXT, MX, NS, A, CAA, aula-lab, impresora, mail, ns1, ns2, portal, resolutor, srv-horizonte, www y el SOA final, más un registro `TSIG hmac-sha256`; `XFR size: 17 records`, por **TCP** | Con la clave la transferencia se permite y va **firmada** (el registro TSIG lleva la firma HMAC, no el secreto). Las transferencias usan TCP. |
| `dig @10.10.10.2 CH TXT version.bind +short` | `"no disponible"` | La versión de BIND está oculta (`version "no disponible"`): no se le regala información a un atacante sobre qué vulnerabilidades buscar. |

## Parte D — NOTIFY y el serial
**1. Nuevo registro subiendo el serial.** En ns1 se agregó `biblioteca IN A 10.10.10.80`, el serial pasó de
`2026100701` a `2026100702` y se aplicó con `instalar_ns1.sh` (`named-checkzone` → `loaded serial 2026100702`,
`rndc reload` → `server reload successful`). Sin hacer nada en ns2, la consulta
`dig @10.10.10.3 biblioteca.horizonte.internal +short` respondió **`10.10.10.80`**: ns1 envió un **NOTIFY** a
ns2 (`also-notify`), ns2 comparó el serial, vio que era mayor y pidió la zona por transferencia firmada con TSIG.
El cambio llegó a ns2 en segundos, sin esperar el `refresh` de 1 hora.

Líneas de `journalctl -u named` en ns2:
```
08:44:33 zone horizonte.internal/IN: notify from 10.10.10.2#36848: serial 2026100702
08:44:34 zone horizonte.internal/IN: Transfer started.
08:44:34 transfer of 'horizonte.internal/IN' from 10.10.10.2#53: connected using 10.10.10.2#53 TSIG transferencia-horizonte
08:44:34 transfer of 'horizonte.internal/IN' from 10.10.10.2#53: Transfer status: success
08:44:34 transfer of 'horizonte.internal/IN' from 10.10.10.2#53: Transfer completed: 1 messages, 18 records, 567 bytes, 0.008 secs (70875 bytes/sec) (serial 2026100702)
08:44:34 zone 10.10.10.in-addr.arpa/IN: notify from 10.10.10.2#59497: zone is up to date
```
**¿Cuánto tardó?** El NOTIFY llegó a las 08:44:33 y la transferencia terminó a las 08:44:34: **alrededor de un
segundo**, de los cuales la copia en sí tardó 0,008 s (18 registros, 567 bytes). La conexión va firmada con la
clave **TSIG `transferencia-horizonte`**. La zona inversa, que no cambió, respondió "zone is up to date".

> Aviso encontrado: `file does not end with newline`. Al agregar la última línea no se pulsó Enter; BIND lo
> tolera pero lo correcto es que el archivo de zona termine en salto de línea.

**2. Nuevo registro sin subir el serial.** Se agregó `cafeteria IN A 10.10.10.81` dejando el serial en
`2026100702` y se recargó ns1.

```
dig @10.10.10.2 cafeteria.horizonte.internal +short   →  10.10.10.81
dig @10.10.10.3 cafeteria.horizonte.internal +short   →  (vacío)
```

En el journal de ns2 quedó registrado el aviso, pero sin transferencia:
```
08:52:28 zone horizonte.internal/IN: notify from 10.10.10.2#49521: zone is up to date
```
ns1 responde porque recargó su archivo, pero **ns2 no se enteró**: el secundario decide si copia la zona
comparando el serial, y como el serial no cambió, para ns2 su copia ya está al día. Ambos servidores quedan
respondiendo distinto para el mismo nombre (incoherencia): según a cuál pregunte un cliente, `cafeteria` existe o
no. Por eso el comentario de la zona dice "¡súbelo en CADA cambio!". Se corrigió subiendo el serial a
`2026100703`: ns2 recibió el NOTIFY y copió la zona (08:56:31, `Transfer completed: … 19 records … (serial
2026100703)`), y `dig @10.10.10.3 cafeteria.horizonte.internal +short` respondió `10.10.10.81`.

**3. ¿Qué pasaría si bajas el serial (por ejemplo, al restaurar un respaldo viejo)?**
ns2 vería un serial **menor** que el de su copia y lo interpretaría como una versión más vieja: no transfiere nada y
sigue sirviendo su copia. Los cambios del primario no llegarían nunca al secundario hasta que el serial vuelva a
superar al que tiene ns2. Soluciones: subir el serial por encima del último usado (por ejemplo, la fecha de hoy
con un `nn` mayor) o forzar la copia en el secundario con `rndc retransfer horizonte.internal`. Por eso el formato
AAAAMMDDnn es útil: siempre crece con la fecha.

## Reflexión
**Si ns1 se apaga**, el DNS del colegio **sigue funcionando**: ns2 tiene una copia completa de las dos zonas y
responde con autoridad (`aa`), y los resolutores prueban el otro NS de la lista. Lo que no se puede hacer es
**cambiar** la zona, porque las modificaciones se hacen en el primario.

**Si ns1 se apaga durante 3 semanas**, ns2 intenta contactarlo cada `refresh` (1 h) y, si falla, cada `retry`
(10 min). Cuando pasa el tiempo de `expire` del SOA (`1209600` s = **2 semanas**) sin poder contactar al primario,
ns2 considera que su copia ya no es confiable y **deja de responder** por la zona (SERVFAIL). A las 3 semanas,
entonces, **todo el DNS del colegio cae**: www, portal, mail, la impresora y el aula. Con él dejan de funcionar el
sitio, el correo y cualquier servicio que dependa de los nombres. Por eso hay que vigilar el primario, tener
respaldos y, si la caída va a ser larga, promover el secundario a primario antes de que venza el `expire`.


## Defensa — Rol Registros (Jacqueline Cáceres)
Explico los registros de la zona: A (www → 10.10.10.20), CNAME (portal → www), MX 10 mail,
TXT con SPF "v=spf1 mx -all" y CAA. En la zona inversa los PTR traducen IP → nombre.
Un nombre sin punto final se completa con $ORIGIN; por eso en la inversa
"www.horizonte.internal." debe llevar el punto.

# Bitácora de uso de IA — Laboratorio 6 (Radiografía DNS)

Estudiante: Lizeth Rodríguez · Entorno: Docker (`horizonte-servidor-lab02`), DiG 9.18.39 · Fecha: 14/10/2026

Reglas que respeté (sección 7 de la guía):
- Todo dato de un dominio se consultó con `dig` en mi servidor; no acepté lo que la IA "sabía" de memoria.
- La IA me explicó la lógica y la sintaxis de bash de los TODO, y yo los escribí y probé en el script.
- Usé los datos de los dominios solo para el diagnóstico, sin pruebas no autorizadas.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Por qué `cd $HOME\...` y `docker cp` fallaban. | Estaba en CMD, no en PowerShell; `$HOME` solo existe en PowerShell. | En PowerShell la copia dio `Successfully copied`. | Diferenciar CMD de PowerShell antes de pegar comandos. |
| 2 | Cómo leer la salida de `dig +trace`. | Cada bloque es un salto: raíz → TLD → autoritativo; `Received … from` dice quién respondió y el tiempo. | Identifiqué los 4 saltos en mi traza (1.1.1.1, m.root, ns.nic.bo, ns5.megalink.com). | Las referencias (delegaciones) llevan hasta el dueño de la zona. |
| 3 | Qué significa cada número del SOA y el error del RNAME. | Serial, refresh, retry, expire y TTL negativo; un nombre sin punto final recibe el origen de la zona. | Mi SOA de upds.edu.bo: `2026081101 28800 7200 1209600 7200` y RNAME terminado en `.upds.edu.bo.`. | El punto final significa "nombre completo". |
| 4 | Por qué el TTL no bajó (300 y 300). | 1.1.1.1 es anycast con cachés separadas; si el registro no está en caché, entrega el TTL completo. | Repetí 4 veces: 290 → 285 → 279 → 274. | Cómo funciona la caché del resolutor; "la propagación" son TTL que vencen. |
| 5 | Sintaxis del TODO 1 (`grep -q`, `awk`, `$(...)`, agregar a una variable). | `grep -q` solo devuelve sí/no; `awk '$4=="SOA"{print $7}'` saca el serial; `VAR="$VAR nuevo"`. | El script detectó `❌ Delegación coja: ns6.megalink.com.` y el serial 2026081101. | Qué es la bandera `aa` y para qué sirve `+norec`. |
| 6 | Cómo sacar la política DMARC. | Copiar el modelo del SPF y usar `grep -o 'p=[a-z]*' \| head -1`. | `✅ DMARC con política p=quarantine` (upds) y `p=reject` (cloudflare). | `head -1` evita confundir `p=` con `sp=`. |
| 7 | Cómo detectar CAA y DNSSEC. | CAA: comprobar si la consulta devuelve algo (`-n`). DNSSEC: buscar el DS y la bandera `ad` con `+dnssec` sin `+short`. | cloudflare.com: CAA y DNSSEC ✅; upds.edu.bo: ❌ en ambos. `verificar_lab06.sh` → 12 de 12. | El DS vive en el padre; `ad` indica que el resolutor validó las firmas. |
| 8 | Por qué una ejecución mostró ✅ falsos y `no servers could be reached`. | Algunas consultas no respondieron en 3 s; el script comparó valores vacíos. | Repetí la radiografía y salió el resultado correcto (6 de 12). | Si aparece un error de `dig`, hay que repetir antes de concluir. |
| 9 | Por qué `bash radiografia_dns.sh dominio1` daba puntaje 0. | `dominio1` era un ejemplo; hay que escribir un dominio real. | Con bnb.com.bo y eldeber.com.bo el script funcionó. | El script detecta dominios inexistentes y se detiene. |
| 10 | Ideas de recomendaciones para los 2 dominios. | Alinear NS, A en el dominio raíz, SPF `-all`, CAA, DNSSEC. | Cada recomendación sale de un ❌ o ⚠️ real de mi radiografía. | Analizar como consultora: hallazgo → riesgo → mejora concreta. |

## Conclusión
La IA me ayudó a entender las salidas de `dig`, los campos del SOA y la sintaxis de bash para los TODO, pero
cada dato del informe sale de mis propias consultas. Dos veces el resultado no fue el esperado (el TTL que no
bajaba y la ejecución con ✅ falsos) y en ambos casos la solución fue repetir la prueba y entender la causa,
no aceptar la primera salida.

// dnsconfig.js — La zona PÚBLICA del colegio escrita como código (DNSControl).
// Flujo profesional: editar → dnscontrol check → dnscontrol preview (ver el diff) → dnscontrol push (aplicar).
// Aquí el proveedor es BIND (genera zonas/ue-horizonte.example.zone). Cambiando creds.json a Cloudflare, el MISMO
// archivo publicaría la zona real en internet. ".example" está reservado para documentación (RFC 2606).

var REG_NINGUNO = NewRegistrar("none");
var DNS_BIND    = NewDnsProvider("bind");

var IP_WEB  = "203.0.113.20";   // 203.0.113.0/24: rango reservado para documentación (RFC 5737)
var IP_MAIL = "203.0.113.25";

D("ue-horizonte.example", REG_NINGUNO, DnsProvider(DNS_BIND),
    DefaultTTL(3600),
    // SOA: primario, correo del responsable (¡con punto final!), refresh, retry, expire, TTL negativo
    // TODO: SOA("@", primario, responsable con punto final, 3600, 600, 1209600, 300) — sin él sale "default_not_set"
    SOA("@", "ns1.ue-horizonte.example.", "ti.ue-horizonte.example.", 3600, 600, 1209600, 300),
    NAMESERVER("ns1.ue-horizonte.example."),
    NAMESERVER("ns2.ue-horizonte.example."),
    A("ns1", "203.0.113.2"),
    A("ns2", "198.51.100.3"),                 // el secundario en OTRA red (redundancia real)

    A("@",   IP_WEB),
    A("www", IP_WEB),
    CNAME("portal", "www"),

    MX("@", 10, "mail"),
    A("mail", IP_MAIL),
    SPF_BUILDER({ label: "@", parts: ["v=spf1", "mx", "-all"] }),
    // TODO: DMARC_BUILDER con política quarantine y reportes a dmarc@ue-horizonte.example
    DMARC_BUILDER({ policy: "quarantine", rua: ["mailto:dmarc@ue-horizonte.example"] }),

    // TODO: CAA_BUILDER: solo letsencrypt.org emite, ningún comodín (issuewild "none"), avisos a ti@…
    CAA_BUILDER({ label: "@", iodef: "mailto:ti@ue-horizonte.example", issue: ["letsencrypt.org"], issuewild: "none" }),
    TXT("@", "google-site-verification=ejemplo-no-real")
);

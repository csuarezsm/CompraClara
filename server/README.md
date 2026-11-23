# CompraClara · servidor

API para cuentas, copia de seguridad en la nube y precios compartidos entre usuarios.
Node 22 + Express + PostgreSQL 16, en Docker.

## Aislamiento en el VPS

- Proyecto Docker propio (`name: compraclara`), contenedores `compraclara-db` y `compraclara-api`.
- Red `compraclara_net` y volumen `compraclara_pgdata` propios.
- La API solo escucha en `127.0.0.1:8095` (no se abre ningún puerto público).
  El proxy inverso que ya uses (nginx, Caddy, Traefik…) publica `https://compraclara.itcanarias.com`.
- No toca otros contenedores, redes ni volúmenes.

## Despliegue

```bash
# 1. Comprobar que el puerto está libre (si no, cambia API_PORT en .env)
ss -ltnp | grep 8095 || echo libre

# 2. Copiar la carpeta server/ al VPS, por ejemplo en /opt/compraclara
cd /opt/compraclara
cp .env.example .env
# Rellenar con: openssl rand -hex 32   (uno distinto para cada variable)
nano .env

# 3. Arrancar solo este proyecto
docker compose -p compraclara up -d --build
docker compose -p compraclara ps
curl -s http://127.0.0.1:8095/v1/health
```

### Catálogo de supermercados (una vez y luego cada mes)

```bash
# Carga los supermercados de Canarias desde OpenStreetMap y fusiona los duplicados creados por usuarios
docker compose -p compraclara run --rm api node src/import_osm.js
# Cada mes (crontab -e):
# 0 4 1 * * cd /opt/compraclara && docker compose -p compraclara run --rm api node src/import_osm.js >> /var/log/compraclara-osm.log 2>&1
```

### Panel de duplicados

`https://compraclara.itcanarias.com/admin` con la clave `ADMIN_TOKEN` del `.env`: muestra los
supermercados que pueden estar repetidos (avisos de usuarios y tiendas creadas a menos de ~140 m de otra)
con botones «Unir» y «Son distintos». Al unir, los precios pasan al supermercado bueno.

### Proxy inverso (ejemplo nginx)

```nginx
server {
    server_name compraclara.itcanarias.com;
    client_max_body_size 25m;
    location / {
        proxy_pass http://127.0.0.1:8095;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    # listen 443 ssl; … (certificado con certbot --nginx -d compraclara.itcanarias.com)
}
```

Después: `nginx -t && systemctl reload nginx` (comprobar antes con `-t` para no afectar a otras webs).

### Copias de la base de datos

```bash
docker exec compraclara-db pg_dump -U compraclara compraclara | gzip > /opt/backups/compraclara-$(date +%F).sql.gz
```

## API

| Método | Ruta | Qué hace |
| --- | --- | --- |
| GET | /v1/health | Estado |
| POST | /v1/auth/register | Alta `{email, password}` → `{token}` |
| POST | /v1/auth/login | Entrar → `{token}` |
| DELETE | /v1/account | Borra la cuenta y su copia |
| PUT / GET | /v1/backup | Sube / descarga la copia completa |
| GET | /v1/backup/info | Fecha y tamaño de la copia |
| POST | /v1/prices | Aporta precios (anónimos) |
| GET | /v1/prices?lat&lng&radius_km&eans | Precios de la comunidad cerca |
| POST | /v1/prices/report | «Este precio no es correcto» |
| GET | /v1/chains | Cadenas de supermercados |
| GET | /v1/stores/nearby?lat&lng&radius_km | Supermercados del catálogo cerca (sin cuenta) |
| POST | /v1/stores | Alta de un súper que falta (si ya existe, devuelve ese) |
| POST | /v1/stores/:id/same-as | Avisar de que está repetido |
| GET / POST | /v1/admin/… | Duplicados, unir y descartar (cabecera `X-Admin-Token`) |

## Supermercados sin duplicados

- Cada supermercado se identifica por **cadena + ubicación** (y su id de OpenStreetMap), no por el nombre.
- La app muestra los cercanos del catálogo para elegir; escribir a mano es el último recurso y la cadena
  se elige de una lista.
- Alta manual: si ya hay uno de la misma cadena a menos de 100 m (o con nombre parecido a menos de 150 m),
  se devuelve ese en vez de crear otro.
- La importación mensual de OpenStreetMap fusiona los creados por usuarios que coinciden con uno oficial.
- El resto se revisa en `/admin`. Datos © colaboradores de OpenStreetMap (ODbL).

## Reglas de calidad de precios

- Las aportaciones no guardan el usuario: solo una clave HMAC para contar personas distintas.
- De ticket o etiqueta → válidas al momento; manuales → válidas cuando otra persona confirma
  el mismo precio (±5 %) en 7 días.
- Fuera de rango (×3 o ÷3 de la mediana reciente) → descartadas.
- 3 avisos de «precio incorrecto» de personas distintas → descartado.
- Ofertas caducadas fuera; datos de más de 90 días fuera; mediana de los últimos 30 días.
- Límite de 300 aportaciones por persona y día; 120 peticiones por minuto.

Pruebas de las reglas: `npm test`.

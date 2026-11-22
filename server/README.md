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

## Reglas de calidad de precios

- Las aportaciones no guardan el usuario: solo una clave HMAC para contar personas distintas.
- De ticket o etiqueta → válidas al momento; manuales → válidas cuando otra persona confirma
  el mismo precio (±5 %) en 7 días.
- Fuera de rango (×3 o ÷3 de la mediana reciente) → descartadas.
- 3 avisos de «precio incorrecto» de personas distintas → descartado.
- Ofertas caducadas fuera; datos de más de 90 días fuera; mediana de los últimos 30 días.
- Límite de 300 aportaciones por persona y día; 120 peticiones por minuto.

Pruebas de las reglas: `npm test`.

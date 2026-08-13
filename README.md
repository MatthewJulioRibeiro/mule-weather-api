# mule-weather-api

Portfolio demo API built with **Mule 4** (Anypoint / MuleSoft), showing HTTP orchestration, DataWeave transformation, and error handling against two real public APIs. Personal, non-commercial demo — part of [matheusribeiro.dev.br](https://matheusribeiro.dev.br).

## What it does

`GET /api/weather?city={city name}`

1. **HTTP Listener** receives the request and reads the `city` query param.
2. **HTTP Request** calls Open-Meteo's free geocoding API to resolve the city name into coordinates — wrapped in a **Cache scope** (Object Store, 1h TTL) so repeat lookups for the same city skip the upstream call, and an **Until Successful** retry (2 attempts) for transient failures.
3. **DataWeave** extracts the first match; raises a custom `WEATHER:CITY_NOT_FOUND` error if nothing matched.
4. **Scatter-Gather**: forecast and air-quality are fetched from Open-Meteo *in parallel*, both keyed off the coordinates resolved above. Air quality is a nice-to-have — if it fails (even after retrying) the response degrades gracefully (`airQuality: null`) instead of failing the whole request.
5. **DataWeave** reshapes everything into clean JSON (temperature, wind, air quality, a human-readable PT/EN description mapped from the WMO weather code).
6. An **error handler** turns validation/upstream failures into proper HTTP status codes (400/404/502/500) instead of leaking stack traces.

`GET /api/weather/compare?cities=city1,city2,...`

Runs the exact same resolver above for every city *concurrently* (Mule's Parallel For Each), and returns one result per city — a failure for one city (not found, upstream down) never fails the others; each entry reports its own `ok`/`error` status. Both endpoints share one `resolve-city-weather` sub-flow, so there's no duplicated orchestration logic between them.

`GET /api/geocode?q={free text, 3+ chars}`

Server-side proxy to [Photon](https://photon.komoot.io), Komoot's free OpenStreetMap-based autocomplete geocoder, reshaped down to `{ label, city, state, country, neighborhood }` per result — powers the location search box on the demo widget (country/state/neighborhood-level suggestions), something Open-Meteo's own geocoder doesn't expose. Photon was picked over OpenStreetMap's own Nominatim `/search` specifically because Nominatim doesn't handle partial words typed mid-search well (e.g. "Vila Mad" while typing "Vila Madalena" matches unrelated places literally named "Mad"); Photon is built for autocomplete and gets it right from the first few characters. Runs server-side, not client-side, because Photon's public instance sends no CORS headers so a browser can't call it directly. Only the resolved `city` field is what actually goes into `/api/weather` — the rest is just for disambiguating the suggestion in the UI.

No API keys anywhere — [Open-Meteo](https://open-meteo.com) is free and keyless, so there's nothing secret to configure or leak.

```bash
curl "https://mule-demo.matheusribeiro.dev.br/api/weather?city=Indaiatuba"
```

Interactive API docs (Swagger UI, self-hosted, no Anypoint Exchange dependency): [mule-demo.matheusribeiro.dev.br/docs/](https://mule-demo.matheusribeiro.dev.br/docs/) — spec source at [`docs/openapi.yaml`](docs/openapi.yaml). CORS is open (`Access-Control-Allow-Origin: *`) so it can also be called straight from a browser — see the live demo widget on [matheusribeiro.dev.br](https://matheusribeiro.dev.br).

```json
{
  "city": "Indaiatuba",
  "country": "Brazil",
  "coordinates": { "latitude": -23.09, "longitude": -47.21 },
  "temperatureCelsius": 24.3,
  "windSpeedKmh": 8.6,
  "description": { "pt": "Céu limpo", "en": "Clear sky" },
  "observedAt": "2026-08-11T14:00"
}
```

## Project layout

```
src/main/mule/weather-api.xml   # the actual Mule flow (HTTP Listener, 2x HTTP Request, DataWeave, error-handler)
pom.xml                          # Maven build -> mule-application package
Dockerfile                       # multi-stage build: mvn package, then bundled with the Mule runtime
docker-entrypoint.sh             # starts Mule and streams its log file to stdout for `docker logs`
```

## Running it yourself

Mule's standalone runtime is a licensed binary MuleSoft doesn't allow redistributing, so it isn't in this repo. To build the image:

1. Download the **Mule Standalone Runtime** from [mulesoft.com/lp/dl/anypoint-mule-studio](https://www.mulesoft.com/lp/dl/anypoint-mule-studio) (free registration).
2. Save it as `runtime/mule-standalone.zip`.
3. `docker build -t mule-weather-api .`
4. `docker run -p 8081:8081 mule-weather-api`

No Enterprise license is installed or required — the app only uses Community-tier features (HTTP Connector, core DataWeave transforms), so the runtime runs indefinitely, not as a time-boxed trial.

## Deploy

`.github/workflows/deploy.yml` builds the Docker image and redeploys it over SSH on every push to `main`, onto a small Oracle Cloud "Always Free" VM. Same CI/CD pattern used on the main portfolio site (GitHub Actions -> deploy on push).

# mule-weather-api

Portfolio demo API built with **Mule 4** (Anypoint / MuleSoft), showing HTTP orchestration, DataWeave transformation, and error handling against two real public APIs. Personal, non-commercial demo — part of [matheusribeiro.dev.br](https://matheusribeiro.dev.br).

## What it does

`GET /api/weather?city={city name}`

1. **HTTP Listener** receives the request and reads the `city` query param.
2. **HTTP Request #1** calls Open-Meteo's free geocoding API to resolve the city name into coordinates.
3. **DataWeave** extracts the first match; raises a custom `WEATHER:CITY_NOT_FOUND` error if nothing matched.
4. **HTTP Request #2** calls Open-Meteo's free forecast API with those coordinates.
5. **DataWeave** reshapes the response into clean JSON (temperature, wind, a human-readable PT/EN description mapped from the WMO weather code).
6. An **error handler** turns validation/upstream failures into proper HTTP status codes (400/404/502/500) instead of leaking stack traces.

No API keys anywhere — [Open-Meteo](https://open-meteo.com) is free and keyless, so there's nothing secret to configure or leak.

```bash
curl "https://mule-demo.matheusribeiro.dev.br/api/weather?city=Indaiatuba"
```

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

# Stage 1: package the Mule application into a deployable jar
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml mule-artifact.json ./
COPY src ./src
RUN mvn -q -B clean package -DskipTests

# Stage 2: bundle the (manually downloaded, license-gated) Mule Standalone
# Runtime with the built app. The zip is NOT committed to this repo -- see
# README.md for how to obtain it before building this image.
FROM eclipse-temurin:17-jre-jammy
ENV MULE_HOME=/opt/mule

RUN apt-get update && apt-get install -y --no-install-recommends unzip curl \
    && rm -rf /var/lib/apt/lists/*

COPY runtime/mule-standalone.zip /tmp/mule-standalone.zip
RUN mkdir -p /opt/mule_extract \
    && cd /opt/mule_extract \
    && unzip -q /tmp/mule-standalone.zip \
    && EXTRACTED_DIR=$(ls /opt/mule_extract) \
    && mv "/opt/mule_extract/${EXTRACTED_DIR}" /opt/mule \
    && rmdir /opt/mule_extract \
    && rm /tmp/mule-standalone.zip \
    # Tune JVM heap for a 1GB host (Oracle Cloud Always Free) -- no Enterprise
    # license is installed, so this runs as Mule Community Edition with no
    # expiration.
    && echo "wrapper.java.additional.90=-Xms256m" >> /opt/mule/conf/wrapper.conf \
    && echo "wrapper.java.additional.91=-Xmx640m" >> /opt/mule/conf/wrapper.conf

COPY --from=build /app/target/*.jar /opt/mule/apps/weather-api.jar
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 8081
WORKDIR /opt/mule
ENTRYPOINT ["/docker-entrypoint.sh"]

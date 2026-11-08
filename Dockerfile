# Base images are pinned by exact tag AND digest: a tag can be republished with
# different contents (new system libraries inside), a digest can't. Dependabot
# (.github/dependabot.yml) opens a PR when the image behind the tag changes,
# and CI builds that PR, so an image update shows up as a tested PR instead of
# a build that breaks overnight.

# Stage 1: package the Mule application into a deployable jar. CI runs this
# same stage (docker build --target build), so the compile check uses exactly
# the Maven/JDK that the deploy uses.
FROM maven:3.9.16-eclipse-temurin-17@sha256:1a352420f7aba21f5ad08df31bab55f74c013fb491f1ae8ab1dd7ff9ed698584 AS build
WORKDIR /app
COPY pom.xml mule-artifact.json ./
COPY src ./src
RUN mvn -q -B clean package -DskipTests

# Stage 2: bundle the (manually downloaded, license-gated) Mule Standalone
# Runtime with the built app. The zip is NOT committed to this repo -- see
# README.md for how to obtain it before building this image.
FROM eclipse-temurin:22.0.2_9-jre-jammy@sha256:dbcae8b5dd4d63f81739a538ec2c09797735f04a21d814f9071b62f018326043
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

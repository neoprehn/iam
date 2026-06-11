# neo4j-migrations CLI als Container (AE-02, container-only nach AE-15).
# Kein gepflegtes offizielles Image vorhanden -> wir bauen ein gepinntes selbst (AE-14):
# JVM-Distribution von neo4j-migrations auf Eclipse Temurin 21 (JRE).
FROM eclipse-temurin:21-jre-jammy

ARG NM_VERSION=4.1.0
ADD https://github.com/michael-simons/neo4j-migrations/releases/download/${NM_VERSION}/neo4j-migrations-${NM_VERSION}.zip /tmp/nm.zip

RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip \
 && unzip -q /tmp/nm.zip -d /opt \
 && rm /tmp/nm.zip \
 && chmod +x /opt/neo4j-migrations-${NM_VERSION}/bin/neo4j-migrations \
 && ln -s /opt/neo4j-migrations-${NM_VERSION}/bin/neo4j-migrations /usr/local/bin/neo4j-migrations \
 && apt-get purge -y unzip \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# Verbindungs-Defaults; Passwort kommt zur Laufzeit aus der Umgebung (NEO4J_PASSWORD).
ENV NEO4J_ADDRESS=bolt://neo4j:7687 \
    NEO4J_USERNAME=neo4j \
    NEO4J_MIGRATIONS_LOCATION=file:/migrations

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /migrations
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["migrate"]

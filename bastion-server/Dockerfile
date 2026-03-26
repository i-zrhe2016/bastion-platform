FROM maven:3.9.11-eclipse-temurin-17 AS builder
WORKDIR /workspace

COPY pom.xml ./pom.xml
COPY bastion-server/pom.xml ./bastion-server/pom.xml
RUN mvn -pl bastion-server -am dependency:go-offline

COPY bastion-server/src ./bastion-server/src
RUN mvn -pl bastion-server -am clean package spring-boot:repackage -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app

COPY --from=builder /workspace/bastion-server/target/bastion-server-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

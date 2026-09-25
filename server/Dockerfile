# Build from the repository root so the shared core package is in context:
#   docker build -f server/Dockerfile -t jobwalk-api .
#   docker run -p 8080:8080 -e ANTHROPIC_API_KEY=... -v jobwalk-data:/data jobwalk-api
FROM dart:stable AS build
WORKDIR /src

# Resolve dependencies first so they are cached across source changes.
COPY packages/core/pubspec.yaml packages/core/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get

COPY packages/core packages/core
COPY server server
RUN cd server && dart pub get --offline \
  && dart compile exe bin/server.dart -o /out/server \
  && mkdir -p /out/data

# Minimal image: the AOT binary plus the Dart runtime files (libc, CA certs).
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
# Published quotes and waitlist signups. Mount a volume here.
COPY --from=build --chown=65534:65534 /out/data /data
ENV JOBWALK_DATA_DIR=/data
USER 65534:65534
EXPOSE 8080
CMD ["/app/server"]

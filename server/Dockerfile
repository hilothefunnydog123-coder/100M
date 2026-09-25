# Build from the repository root so the shared core package is in context:
#   docker build -f server/Dockerfile -t jobwalk-api .
# Or run everything locally with Postgres: docker compose up
FROM dart:stable AS build
WORKDIR /src

# Resolve dependencies first so they are cached across source changes.
COPY packages/core/pubspec.yaml packages/core/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get

COPY packages/core packages/core
COPY server server
ARG VERSION=dev
RUN mkdir -p /out/data/objects && cd server && dart pub get --offline \
  && for bin in server migrate worker; do \
       dart compile exe bin/$bin.dart -o /out/$bin \
         --define=JOBWALK_VERSION=$VERSION || exit 1; \
     done

# Minimal image: AOT binaries plus the Dart runtime files (libc, CA certs).
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /out/migrate /out/worker /app/
# Photos when STORAGE=file. Mount a volume here, or use STORAGE=s3.
COPY --from=build --chown=65534:65534 /out/data /data
ENV STORAGE_DIR=/data/objects
USER 65534:65534
EXPOSE 8080
CMD ["/app/server"]

# The admin viewer (docs/SECURITY.md -> "The admin viewer"): the React app is built first
# and published as the service's static files. The build context is `admin/` alone - the
# viewer needs nothing outside it:
#
#   docker build -t tankbook-admin:<tag> admin
#   docker run --rm -p 127.0.0.1:8081:8080 \
#     -e ConnectionStrings__ApiRead="Host=...;Database=tankbook;Username=tankbook_admin_ro;Password=..." \
#     -e ConnectionStrings__AdminWrite="Host=...;Database=tankbook;Username=tankbook_admin_rw;Password=..." \
#     -e Admin__BootstrapToken=... \
#     tankbook-admin:<tag>
#
# Deployment (nginx, TLS, CI) is AD.8; this image carries no secret.

FROM --platform=$BUILDPLATFORM node:22-alpine AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npx vite build --outDir /wwwroot --emptyOutDir

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
WORKDIR /src
COPY api/src/Tankbook.Admin/Tankbook.Admin.csproj api/src/Tankbook.Admin/
RUN dotnet restore api/src/Tankbook.Admin/Tankbook.Admin.csproj -r linux-$TARGETARCH
COPY api/src/ api/src/
RUN rm -f api/src/Tankbook.Admin/appsettings.Development.json
COPY --from=web /wwwroot api/src/Tankbook.Admin/wwwroot/
RUN dotnet publish api/src/Tankbook.Admin/Tankbook.Admin.csproj \
    --configuration Release \
    -r linux-$TARGETARCH \
    --self-contained false \
    --no-restore \
    --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
USER $APP_UID
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_gcServer=0
EXPOSE 8080
COPY --from=build /app .
ENTRYPOINT ["dotnet", "Tankbook.Admin.dll"]

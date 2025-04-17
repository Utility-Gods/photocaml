# ---- Build Stage ----
    FROM ocaml/opam:debian-ocaml-4.14 AS build
    WORKDIR /app
    COPY . .
   
    RUN sudo chown -R opam:opam /app
    ENV OPAMSOLVERTIMEOUT=1800
    RUN sudo apt-get update && sudo apt-get install -y \
    libpq-dev pkg-config m4 libev-dev zlib1g-dev libssl-dev build-essential \
    libgmp-dev libpcre3-dev libffi-dev \
    && opam install . --deps-only -y \
    && eval $(opam env) \
    && dune build bin/main.exe
    
    # ---- Run Stage ----
    FROM debian:bullseye-slim
    WORKDIR /app
    COPY --from=build /app/_build/default/bin/main.exe /app/main.exe
    COPY --from=build /app/_build/default/scripts/db/init_pg.exe /app/init_pg.exe
    COPY --from=build /app/static /app/static
    COPY --from=build /app/.env /app/.env
    COPY --from=build /app/lib /app/lib
    COPY --from=build /app/scripts /app/scripts
    
    EXPOSE 4000
    
    ENTRYPOINT ["/app/entrypoint.sh"]
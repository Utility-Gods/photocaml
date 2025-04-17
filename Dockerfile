# ---- Build Stage ----
    FROM ocaml/opam:debian-ocaml-5.2 AS build
    WORKDIR /app
    COPY . .
   
    RUN sudo chown -R opam:opam /app
    ENV OPAMSOLVERTIMEOUT=3600
    # Install system deps and clean up apt cache
    RUN sudo apt-get update && sudo apt-get install -y \
        libpq-dev pkg-config m4 libev-dev zlib1g-dev libssl-dev build-essential \
        libgmp-dev libpcre3-dev libffi-dev \
        && sudo rm -rf /var/lib/apt/lists/*

    # Use a fresh opam switch for reproducibility
    RUN opam switch create . ocaml-base-compiler.5.2.1 || true
    # Update opam repo and install deps with default solver (builtin-0install not available)
    RUN opam update && opam install . --deps-only -y
    # Build project
    RUN eval $(opam env) && dune build bin/main.exe
    
    # ---- Run Stage ----
    FROM debian:bullseye-slim
    WORKDIR /app
    COPY --from=build /app/_build/default/bin/main.exe /app/main.exe
    COPY --from=build /app/_build/default/scripts/db/init_pg.exe /app/init_pg.exe
    COPY --from=build /app/.env /app/.env
    COPY --from=build /app/lib /app/lib
    COPY --from=build /app/scripts /app/scripts
    
    EXPOSE 4000
    
    ENTRYPOINT ["/app/entrypoint.sh"]
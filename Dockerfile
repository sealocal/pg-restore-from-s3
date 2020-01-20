FROM postgres:12.1

# add user with ID 1000 (to support Docker hosting service)
RUN useradd --create-home --shell /bin/bash appuser

RUN postgres --version # postgres (PostgreSQL) 12.1 (Debian 12.1-1.pgdg100+1)
RUN psql --version     # psql (PostgreSQL) 12.1 (Debian 12.1-1.pgdg100+1)

# install awscli
RUN apt-get update && apt-get install --yes \
  python3 \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*
RUN pip3 install awscli

ENV PGDATA /var/lib/postgresql/data/pgdata

USER postgres
COPY ./restore.sh /usr/src/app/
CMD bash /usr/src/app/restore.sh

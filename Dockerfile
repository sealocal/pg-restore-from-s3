FROM postgres:12.1

RUN postgres --version # postgres (PostgreSQL) 12.1 (Debian 12.1-1.pgdg100+1)
RUN psql --version     # psql (PostgreSQL) 12.1 (Debian 12.1-1.pgdg100+1)

# install awscli
RUN apt-get update && apt-get install --yes python3 python3-pip
RUN pip3 install awscli

USER postgres
WORKDIR /var/lib/postgresql/
COPY ./restore.sh /docker-entrypoint-initdb.d/

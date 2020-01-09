FROM postgres:11.6

WORKDIR /usr/src/app
COPY . .

RUN postgres --version # postgres (PostgreSQL) 11.6 (Debian 11.6-1.pgdg90+1)
RUN psql --version     # psql (PostgreSQL) 11.6 (Debian 11.6-1.pgdg90+1)

# install awscli
RUN apt-get update && apt-get install --yes python3 python3-pip
RUN pip3 install awscli

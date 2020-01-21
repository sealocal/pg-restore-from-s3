# Fail fast
set -e

# Parse command-line arguments for this script
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -b|--bucketname)
    BUCKET_NAME="$2"
    shift
    ;;
    -p|--bucketpath)
    BUCKET_PATH="$2"
    shift
    ;;
    -d|--download-path)
    DOWNLOAD_PATH="$2"
    shift
    ;;
    -db|--dbname)
    DATABASE_NAME="$2"
    shift
    ;;
    -url|--dburl)
    DATABASE_URL="$2"
    shift
    ;;
esac
shift
done

BUCKET_NAME=${BUCKET_NAME:='bucket_name'}
BUCKET_PATH=${BUCKET_PATH:='bucket_path'}
DOWNLOAD_PATH=${DOWNLOAD_PATH:='./'}

DATABASE_NAME=${DATABASE_NAME:='database_name'}
DATABASE_URL=${DATABASE_URL:=}
DB_BACKUP_ENC_KEY=${DB_BACKUP_ENC_KEY:=}

if [[ -z "$DATABASE_NAME" ]]; then
  echo "Missing DATABASE_NAME variable"
  exit 1
fi
if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  echo "Missing AWS_ACCESS_KEY_ID variable"
  exit 1
fi
if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "Missing AWS_SECRET_ACCESS_KEY variable"
  exit 1
fi
if [[ -z "$AWS_DEFAULT_REGION" ]]; then
  echo "Missing AWS_DEFAULT_REGION variable"
  exit 1
fi
if [[ -z "$BUCKET_PATH" ]]; then
  echo "Missing BUCKET_PATH variable"
  exit 1
fi
if [[ -z "$DB_BACKUP_ENC_KEY" ]]; then
  echo "Missing DB_BACKUP_ENC_KEY variable"
  exit 1
fi

printf "Looking for latest file in s3://$BUCKET_NAME/$BUCKET_PATH/\n"

LATEST_FILES=$(aws s3 ls s3://$BUCKET_NAME/$BUCKET_PATH/ | tail -n 4 | grep --only-matching $BUCKET_PATH.*enc)

printf "LATEST_FILES:\n$LATEST_FILES\n"

LATEST_CUSTOM_FORMAT=$(   echo "$LATEST_FILES" | grep --only-matching .*custom_format.enc)
LATEST_DIRECTORY_FORMAT=$(echo "$LATEST_FILES" | grep --only-matching .*directory_format.gz.enc)
LATEST_PLAIN_FORMAT=$(    echo "$LATEST_FILES" | grep --only-matching .*plain_format.gz.enc)
LATEST_TAR_FORMAT=$(      echo "$LATEST_FILES" | grep --only-matching .*tar_format.gz.enc)

printf "Latest custom file: $LATEST_CUSTOM_FORMAT\n"
printf "Latest directory file: $LATEST_DIRECTORY_FORMAT\n"
printf "Latest plain file: $LATEST_PLAIN_FORMAT\n"
printf "Latest tar file: $LATEST_TAR_FORMAT\n"

aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_CUSTOM_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_DIRECTORY_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_PLAIN_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_TAR_FORMAT $DOWNLOAD_PATH

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_CUSTOM_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_DIRECTORY_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_PLAIN_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_TAR_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz


if [ -f /.dockerenv ]; then
  printf "*** Create PGDATA directory at $PGDATA ...\n"
  mkdir $PGDATA

  printf "*** Initialize the database directory ...\n"
  pg_ctl initdb

  printf "Start postgres server with database directory ...\n"
  pg_ctl start -l /tmp/postgres.log

  printf "*** Create default database for appuser ...\n"
  createdb appuser
fi

if [[ -n "$DATABASE_URL" ]]; then
  echo "Restore database using DATABASE_URL"
  # custom format
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
  psql --dbname $DATABASE_URL --command "\d"

  # directory format
  tar -zxvf $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz
  UNZIPPED_DIRECTORY=$(ls -dp $DOWNLOAD_PATH/$DATABASE_NAME_*directory_format)
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $DOWNLOAD_PATH/$UNZIPPED_DIRECTORY
  psql --dbname $DATABASE_URL --command "\d"

  # plain format
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_plain_format.sql
  time psql --dbname $DATABASE_URL --file=$UNZIPPED_FILENAME
  psql --dbname $DATABASE_URL --command "\d"

  # tar format
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_tar_format.tar
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar
  psql --dbname $DATABASE_URL --command "\d"
elif [[ -n "$DATABASE_NAME" ]]; then
  echo "Restore database using DATABASE_NAME"
  # custom format
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # directory format
  tar -zxvf $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz --directory=$DOWNLOAD_PATH
  UNZIPPED_DIRECTORY=$(ls -dp $DOWNLOAD_PATH/$DATABASE_NAME_*directory_format)
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $UNZIPPED_DIRECTORY
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # plain format
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz
  UNZIPPED_FILENAME=$DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql
  createdb ${DATABASE_NAME}_restored
  time psql --dbname ${DATABASE_NAME}_restored --file=$UNZIPPED_FILENAME
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # tar format
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_tar_format.tar
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored
fi

if [ -f /.dockerenv ]; then
  printf "*** Stop postgres server with database directory ...\n"
  pg_ctl stop -l /tmp/postgres.log
fi

# cleanup
rm -v $DOWNLOAD_PATH/${DATABASE_NAME}_*.enc
rm -v $DOWNLOAD_PATH/*.gz
rm -v $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
rm -rv $DOWNLOAD_PATH/${DATABASE_NAME}_*directory_format
rm -v $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql
rm -v $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar

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

# Check initial contents of download directory
printf "\n\nInitial contents of DOWNLOAD_PATH ($DOWNLOAD_PATH) ..."
ls -lah $DOWNLOAD_PATH/

printf "Looking for latest file in s3://$BUCKET_NAME/$BUCKET_PATH/\n"

LATEST_FILES=$(aws s3 ls s3://$BUCKET_NAME/$BUCKET_PATH/ | tail -n 4 | grep --only-matching $BUCKET_PATH.*enc)

printf "\n\nLATEST_FILES:\n$LATEST_FILES\n"

LATEST_CUSTOM_FORMAT=$(   echo "$LATEST_FILES" | grep --only-matching .*custom_format.enc)
LATEST_DIRECTORY_FORMAT=$(echo "$LATEST_FILES" | grep --only-matching .*directory_format.gz.enc)
LATEST_PLAIN_FORMAT=$(    echo "$LATEST_FILES" | grep --only-matching .*plain_format.gz.enc)
LATEST_TAR_FORMAT=$(      echo "$LATEST_FILES" | grep --only-matching .*tar_format.gz.enc)

printf "\n\nLatest custom file: $LATEST_CUSTOM_FORMAT\n"
printf "Latest directory file: $LATEST_DIRECTORY_FORMAT\n"
printf "Latest plain file: $LATEST_PLAIN_FORMAT\n"
printf "Latest tar file: $LATEST_TAR_FORMAT\n"

aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_CUSTOM_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_DIRECTORY_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_PLAIN_FORMAT $DOWNLOAD_PATH
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_TAR_FORMAT $DOWNLOAD_PATH

openssl enc -aes-256-cbc -pbkdf2 -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_CUSTOM_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump

openssl enc -aes-256-cbc -pbkdf2 -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_DIRECTORY_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz

openssl enc -aes-256-cbc -pbkdf2 -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_PLAIN_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz

openssl enc -aes-256-cbc -pbkdf2 -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in $DOWNLOAD_PATH/$LATEST_TAR_FORMAT \
  -out $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz

if [[ -n "$DATABASE_URL" ]]; then

  echo "Restore database using DATABASE_URL"
  # custom format
  printf "Restoring custom format ...\n"
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $file_path
  psql --dbname $DATABASE_URL --command "\d"

  # directory format
  printf "\n\nRestoring directory format ...\n"
  dir_path=$DOWNLOAD_PATH/${DATABASE_NAME}_directory_format/
  mkdir $dir_path
  tar -zxvf $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz --strip-components=2 --directory=$dir_path
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $dir_path
  psql --dbname $DATABASE_URL --command "\d"

  # plain format
  printf "\n\nRestoring plain format ...\n"
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql
  time psql --dbname $DATABASE_URL --file=$file_path
  psql --dbname $DATABASE_URL --command "\d"

  # tar format
  printf "\n\nRestoring tar format ...\n"
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar
  time pg_restore --clean --no-owner --dbname $DATABASE_URL $file_path
  psql --dbname $DATABASE_URL --command "\d"

elif [[ -n "$DATABASE_NAME" ]]; then

  if [ -f /.dockerenv ]; then
    printf "\n\n*** Create PGDATA directory at $PGDATA ...\n"
    mkdir $PGDATA

    printf "*** Initialize the database directory ...\n"
    pg_ctl initdb

    printf "Start postgres server with database directory ...\n"
    pg_ctl start -l /tmp/postgres.log

    printf "*** Create default database for appuser ...\n"
    createdb appuser
  fi

  echo "Restore database using DATABASE_NAME"
  # custom format
  printf "\n\nRestoring custom format ...\n"
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $file_path
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # directory format
  printf "\n\nRestoring directory format ...\n"
  dir_path=$DOWNLOAD_PATH/${DATABASE_NAME}_directory_format/
  mkdir $dir_path
  tar -zxvf $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz --strip-components=2 --directory=$dir_path
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $dir_path
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # plain format
  printf "\n\nRestoring plain format ...\n"
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql.gz
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql
  createdb ${DATABASE_NAME}_restored
  time psql --dbname ${DATABASE_NAME}_restored --file=$file_path
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # tar format
  printf "\n\nRestoring tar format ...\n"
  gzip --verbose --decompress $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar.gz
  file_path=$DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored $file_path
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  if [ -f /.dockerenv ]; then
    printf "\n\n*** Stop postgres server with database directory ...\n"
    pg_ctl stop -l /tmp/postgres.log
  fi
fi

# cleanup each of the encrypted backups that were downloaded
rm -v $DOWNLOAD_PATH/$LATEST_CUSTOM_FORMAT
rm -v $DOWNLOAD_PATH/$LATEST_DIRECTORY_FORMAT
rm -v $DOWNLOAD_PATH/$LATEST_PLAIN_FORMAT
rm -v $DOWNLOAD_PATH/$LATEST_TAR_FORMAT

# cleanup each of the unencryped and extracted backups
rm -v  $DOWNLOAD_PATH/${DATABASE_NAME}_custom_format.dump
rm -v  $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format.tar.gz
rm -rv $DOWNLOAD_PATH/${DATABASE_NAME}_directory_format/
rm -v  $DOWNLOAD_PATH/${DATABASE_NAME}_plain_format.sql
rm -v  $DOWNLOAD_PATH/${DATABASE_NAME}_tar_format.tar

# verify empty directory
printf "\n\nFinal contents of DOWNLOAD_PATH ($DOWNLOAD_PATH) ..."
ls -lah $DOWNLOAD_PATH/

printf '\nDone!\n'

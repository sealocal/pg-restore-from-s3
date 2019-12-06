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

aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_CUSTOM_FORMAT ./
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_DIRECTORY_FORMAT ./
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_PLAIN_FORMAT ./
aws s3 cp s3://$BUCKET_NAME/$BUCKET_PATH/$LATEST_TAR_FORMAT ./

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in ./$LATEST_CUSTOM_FORMAT \
  -out ./${DATABASE_NAME}_custom_format.dump

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in ./$LATEST_DIRECTORY_FORMAT \
  -out ./${DATABASE_NAME}_directory_format.tar.gz

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in ./$LATEST_PLAIN_FORMAT \
  -out ./${DATABASE_NAME}_plain_format.sql.gz

openssl enc -aes-256-cbc -d -pass "env:DB_BACKUP_ENC_KEY" \
  -in ./$LATEST_TAR_FORMAT \
  -out ./${DATABASE_NAME}_tar_format.tar.gz

if [[ -n "$DATABASE_URL" ]]; then
  echo "Restore database using DATABASE_URL"
  # custom format
  time pg_restore --clean --no-owner --dbname $DATABASE_URL ./${DATABASE_NAME}_custom_format.dump
  psql --dbname $DATABASE_URL --command "\d"

  # directory format
  tar -zxvf ./${DATABASE_NAME}_directory_format.tar.gz
  UNZIPPED_DIRECTORY=$(ls -dp $DATABASE_NAME_*directory_format)
  time pg_restore --clean --no-owner --dbname $DATABASE_URL ./$UNZIPPED_DIRECTORY
  psql --dbname $DATABASE_URL --command "\d"

  # plain format
  gzip --verbose --decompress ./${DATABASE_NAME}_plain_format.sql.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_plain_format.sql
  time psql --dbname $DATABASE_URL --file=$UNZIPPED_FILENAME
  psql --dbname $DATABASE_URL --command "\d"

  # tar format
  gzip --verbose --decompress ./${DATABASE_NAME}_tar_format.tar.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_tar_format.tar
  time pg_restore --clean --no-owner --dbname $DATABASE_URL ./${DATABASE_NAME}_tar_format.tar
  psql --dbname $DATABASE_URL --command "\d"
elif [[ -n "$DATABASE_NAME" ]]; then
  echo "Restore database using DATABASE_NAME"
  # custom format
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored ./${DATABASE_NAME}_custom_format.dump
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # directory format
  tar -zxvf ./${DATABASE_NAME}_directory_format.tar.gz -s "/${DATABASE_NAME}.*_directory_format/${DATABASE_NAME}_directory_format/"
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored ./${DATABASE_NAME}_directory_format
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # plain format
  gzip --verbose --decompress ./${DATABASE_NAME}_plain_format.sql.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_plain_format.sql
  createdb ${DATABASE_NAME}_restored
  time psql --dbname ${DATABASE_NAME}_restored --file=$UNZIPPED_FILENAME
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored

  # tar format
  gzip --verbose --decompress ./${DATABASE_NAME}_tar_format.tar.gz
  UNZIPPED_FILENAME=${DATABASE_NAME}_tar_format.tar
  createdb ${DATABASE_NAME}_restored
  time pg_restore --no-owner --dbname ${DATABASE_NAME}_restored ./${DATABASE_NAME}_tar_format.tar
  psql --dbname ${DATABASE_NAME}_restored --command "\d"
  dropdb ${DATABASE_NAME}_restored
fi

# cleanup
rm -v ${DATABASE_NAME}_*.enc
rm -v *.gz
rm -v ${DATABASE_NAME}_custom_format.dump
rm -rv ${DATABASE_NAME}_*directory_format
rm -v ${DATABASE_NAME}_plain_format.sql
rm -v ${DATABASE_NAME}_tar_format.tar

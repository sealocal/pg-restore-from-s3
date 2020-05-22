## pg-restore-from-s3

Fetches Postgres backups from an s3 bucket and `pg_restore`s it.

### Dependencies

* awscli (or pip3)
* Postgres client (psql, pg_restore)

### Environment Variables

## Required

```
# credentials to access backups in S3
AWS_ACCESS_KEY_ID=aws-access-key-id
AWS_SECRET_ACCESS_KEY=aws-secret-access-key
AWS_DEFAULT_REGION=us-west-2

# password for decrypting the backups
DB_BACKUP_ENC_KEY=password

# name of the bucket where the backups are stored
BUCKET_NAME=bucket_name
# name of the folder where the backups are stored
BUCKET_PATH=bucket_path
# file path to which backups should be written upon download
DOWNLOAD_PATH=download_path

# The name of the database where the data will be restored.
#
# If TARGET_DATABASE_URL is not present, a local database with the
# name set to TARGET_DATABASE_NAME will be the target for restoring data.
#
# If TARGET_DATABASE_URL is present, then TARGET_DATABASE_NAME is used
# as the base of the name of the files that are downloaded from
# the S3 bucket.
#
TARGET_DATABASE_NAME=database_name
```

## Optional

```
# The url of the database where the data will be restored
#
TARGET_DATABASE_URL=postgres://user:pass@host/database_name
```

## Example Docker Usage

The Dockerfile has everything needed to run the restore script, but several environment variables are required.

```
docker build -t pg_restore_from_s3 .
docker run --rm -it \
    -e AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) \
    -e AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) \
    -e AWS_DEFAULT_REGION=$(aws configure get region) \
    -e DB_BACKUP_ENC_KEY=$DB_BACKUP_ENC_KEY \
    -e BUCKET_NAME=$BUCKET_NAME \
    -e BUCKET_PATH=$BUCKET_PATH \
    -e DOWNLOAD_PATH=/tmp \
    -e TARGET_DATABASE_URL=$TARGET_DATABASE_URL \
    -e FORMAT=custom \
    pg_restore_from_s3
```

# Example Local Usage

Run the build script to install awscli with pip3.

```
bash ./build.sh
```

Run the restore script.

```bash
bash ./restore.sh --bucketname <bucket_name> --bucketpath <bucket_path> --dbname <database_name> --format <custom>
```

```log
--dbname, -db

    string prefix for filename of the Postgres dump

--bucketname, -b

    specify the name of the bucket to fetch files from

--bucketpath, -p

    specify the name of a "folder" in a bucket to fetch files from

--download-path, -d

    specify the name of a "folder" in a bucket to fetch files from

--dburl, -url

    specify the name location of a postgres database for data restore

--format, -f

    specify the format of the database backup to be imported

    The formats correspond to Postgres formats for pg_restore.

    Possible formats for this script are "custom", "directory", "plain", and "tar".

    If this option is omitted, then all formats will be attempted (most useful for CI scripts).
```

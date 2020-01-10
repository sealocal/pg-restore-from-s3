## pg-restore-from-s3

Fetches Postgres backups from an s3 bucket and `pg_restore`s it.

### Dependencies

* awscli (or pip3)
* Postgres client (psql, pg_restore)

### Installation

Run the build script to install awscli with pip3.

```
bash ./build.sh
```

### Environment Variables

```
## required

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

# the name of the database where the data will be restored
DATABASE_NAME=database_name

## optional
# the url of the database where the data will be restored
# if present, DATABASE_NAME is ignored
DATABASE_URL=postgres://user:pass@host/database_name
```

### Example Usage

```bash
bash /app/vendor/restore.sh --bucketname <bucket_name> --bucketpath <bucket_path> --dbname <database_name>
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
```

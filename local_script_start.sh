# Initialize the database
rm -rf $PG_TEST_DIR/data
$PG_TEST_DIR/bin/initdb -D $PG_TEST_DIR/data

# Modify postgresql.conf to enable pg_stat_statements and set port
# check if already done
if grep -q "port = 5433" $PG_TEST_DIR/data/postgresql.conf; then
    echo "config already set"
else
    echo "config will be set"
    echo "port = 5433" >> $PG_TEST_DIR/data/postgresql.conf
    echo "shared_preload_libraries = 'pg_stat_statements'" >> $PG_TEST_DIR/data/postgresql.conf
    echo "pg_stat_statements.track = all" >> $PG_TEST_DIR/data/postgresql.conf
    echo "pg_stat_statements.max = 10000" >> $PG_TEST_DIR/data/postgresql.conf
fi

# Seems to be required by pg_stat_statements
mkdir -p $PG_TEST_DIR/data/pg_stat

# Start the database
$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data -l $PG_TEST_DIR/logfile start

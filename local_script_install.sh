# Create base directory
export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

mkdir -p $PG_TEST_DIR

# ./configure --prefix=$PG_TEST_DIR --without-icu
rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements--*.sql
rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements.control

# Build main PostgreSQL
# make

# Build contrib modules (including pg_stat_statements)
cd contrib/pg_stat_statements
make clean
make
make install

$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data restart -l $PG_TEST_DIR/logfile

# Verify installation
$PG_TEST_DIR/bin/psql -p 5433 test -c "
CREATE EXTENSION pg_stat_statements;
SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
"

# Install everything
# cd ..
# make install

# cd contrib
# make install

# Create base directory
export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
mkdir -p $PG_TEST_DIR

# ./configure --prefix=$PG_TEST_DIR --without-icu

# Build main PostgreSQL
# make

# Build contrib modules (including pg_stat_statements)
cd contrib/pg_stat_statements
make clean
make
make install

# Install everything
# cd ..
# make install

# cd contrib
# make install

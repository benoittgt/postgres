#!/bin/bash
# PostgreSQL build script with pg_stat_statements
#
# Usage:
#   ./local_script_install.sh           # Full build (PostgreSQL + pg_stat_statements)
#   ./local_script_install.sh pgss      # Quick rebuild pg_stat_statements only
#

# Create base directory
export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

mkdir -p $PG_TEST_DIR

# Check if we only want to rebuild pg_stat_statements
# Usage: PGSS_ONLY=1 ./local_script_install.sh
# or: ./local_script_install.sh pgss
if [ "$1" = "pgss" ]; then
    echo "🦀 Quick rebuild: pg_stat_statements only"
    echo "🦀 Clean before rebuilding pg_stat_statements"
    rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements--*.sql
    rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements.control

    # Build only pg_stat_statements
    echo "🦀 Building pg_stat_statements in $PG_TEST_DIR"
    cd contrib/pg_stat_statements
    make clean
    make
    make install
else
    echo "🦀 Full build: PostgreSQL + pg_stat_statements"
    echo "🦀 Configuring PostgreSQL in $PG_TEST_DIR"
    ./configure --prefix=$PG_TEST_DIR --without-icu # can be ignored if already configured
    echo "🦀 Clean before rebuilding pg_stat_statements"
    rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements--*.sql
    rm -f $PG_TEST_DIR/share/postgresql/extension/pg_stat_statements.control

    echo "🦀 Building PostgreSQL in $PG_TEST_DIR"
    make

    echo "🦀 Building contrib modules in $PG_TEST_DIR"
    cd contrib/pg_stat_statements
    make clean
    make
    make install
fi

$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data restart -l $PG_TEST_DIR/logfile

# Verify installation
$PG_TEST_DIR/bin/psql -p 5433 test -c "
CREATE EXTENSION pg_stat_statements;
SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
"
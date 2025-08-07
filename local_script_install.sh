#!/bin/bash
# PostgreSQL build script with pg_stat_statements
#
# Usage:
#   ./local_script_install.sh           # Full build (PostgreSQL + pg_stat_statements)
#   ./local_script_install.sh pgss      # Quick rebuild pg_stat_statements only
#   ./local_script_install.sh cleanup   # Cleanup shared memory and processes
#

# Create base directory
export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

mkdir -p $PG_TEST_DIR

# Function to cleanup PostgreSQL processes and shared memory, it happens during hard testing :D
cleanup_postgres() {
    echo "🧹 Cleaning up PostgreSQL processes and shared memory..."

    # Stop PostgreSQL gracefully
    $PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data stop -m immediate 2>/dev/null || true

    # Wait for graceful shutdown
    sleep 2

    # Force kill any remaining processes
    pkill -f "postgres.*$PG_TEST_DIR" 2>/dev/null || true
    pkill -f "postgres.*pg_test" 2>/dev/null || true
    
    # Kill any PostgreSQL processes running on port 5433
    lsof -ti:5433 | xargs kill -9 2>/dev/null || true
    
    # More specific cleanup - avoid killing system PostgreSQL
    pkill -f "postgres.*port.*5433" 2>/dev/null || true

    # Wait for processes to fully terminate
    sleep 3

    echo "🧹 Removing PostgreSQL data directory..."
    rm -rf $PG_TEST_DIR/data

    echo "🧹 Recreating data directory..."
    mkdir -p $PG_TEST_DIR/data
    
    echo "🧹 Removing shared memory segments..."

    rm -f $PG_TEST_DIR/data/postmaster.pid 2>/dev/null || true

    # Remove all shared memory segments owned by current user
    for shmid in $(ipcs -m | awk -v user="`whoami`" '$3 == user {print $2}'); do
        echo "🧹 Removing shared memory segment: $shmid"
        ipcrm -m $shmid 2>/dev/null || true
    done

    # Clean up semaphores if any
    for semid in $(ipcs -s | awk -v user="`whoami`" '$3 == user {print $2}'); do
        echo "🧹 Removing semaphore: $semid"
        ipcrm -s $semid 2>/dev/null || true
    done

    echo "🧹 Cleanup complete!"
}
# Check if we only want to rebuild pg_stat_statements
# Usage: PGSS_ONLY=1 ./local_script_install.sh
# or: ./local_script_install.sh pgss
if [ "$1" = "cleanup" ]; then
    cleanup_postgres
    exit 0
elif [ "$1" = "pgss" ]; then
    echo "🦀 Quick rebuild: pg_stat_statements only"

    # Clean up first
    cleanup_postgres

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

    # Clean up first
    cleanup_postgres

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

echo "🦀 Installation complete in $PG_TEST_DIR, creating db, starting pg..."

# Initialize database if it doesn't exist
if [ ! -d "$PG_TEST_DIR/data" ] || [ ! -f "$PG_TEST_DIR/data/PG_VERSION" ]; then
    echo "🦀 Initializing database..."
    $PG_TEST_DIR/bin/initdb -D $PG_TEST_DIR/data --locale=C --encoding=UTF8
    
    # Configure PostgreSQL to use port 5433
    echo "🦀 Configuring PostgreSQL to use port 5433..."
    echo "port = 5433" >> $PG_TEST_DIR/data/postgresql.conf
    echo "shared_preload_libraries = 'pg_stat_statements'" >> $PG_TEST_DIR/data/postgresql.conf
    echo "pg_stat_statements.track = all" >> $PG_TEST_DIR/data/postgresql.conf
fi

sleep 2

# Start PostgreSQL
echo "🦀 Starting PostgreSQL on port 5433..."
$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data -o "-p 5433" start -l $PG_TEST_DIR/logfile

# Wait a moment for startup
sleep 5

# Create test database if it doesn't exist
echo "🦀 Creating test database..."
$PG_TEST_DIR/bin/createdb -p 5433 test 2>/dev/null || true

# Verify installation
$PG_TEST_DIR/bin/psql -p 5433 test -c "
CREATE EXTENSION pg_stat_statements;
SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
"

echo "🦀 Installation verification complete, stopping PostgreSQL..."
$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data stop -m fast

echo "🦀 Installation complete! Use './local_script_start.sh' to start PostgreSQL."
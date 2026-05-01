#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo ""

DB2PROFILE=~/sqllib/db2profile

if [ ! -f "$DB2PROFILE" ]; then
  echo "ERROR: db2profile not found at $DB2PROFILE"
  exit 1
fi

run_db2_query() {
  DBNAME="$1"
  SQL="$2"

  . "$DB2PROFILE"

  OUTPUT=$(db2 -x "connect to $DBNAME; $SQL; connect reset;" 2>&1)
  RC=$?

  if [ $RC -ne 0 ]; then
    echo "  ❌ DB2 ERROR on $DBNAME:"
    echo "$OUTPUT"
    return 1
  fi

  # Clean output
  echo "$OUTPUT" | sed '/^$/d' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

. "$DB2PROFILE"
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

echo "Found DBs: $DBS"
echo ""

for DB in $DBS; do
  echo "--------------------------------------------------"
  echo "DATABASE: $DB"

  # DEBUG: show actual tables
  echo "  DEBUG: Checking for Q Rep tables..."
  run_db2_query "$DB" "
    SELECT TABSCHEMA, TABNAME
    FROM SYSCAT.TABLES
    WHERE TABNAME LIKE 'IBMQREP%'
  "

  # Get schemas
  SCHEMAS=$(run_db2_query "$DB" "
    SELECT DISTINCT RTRIM(TABSCHEMA)
    FROM SYSCAT.TABLES
    WHERE TABNAME IN ('IBMQREP_SENDQUEUES','IBMQREP_RECVQUEUES')
  ")

  if [ -z "$SCHEMAS" ]; then
    echo "  ❌ No Q Replication control tables found."
    continue
  fi

  echo "$SCHEMAS" | while read SCHEMA; do
    [ -z "$SCHEMA" ] && continue

    echo "  Q Rep schema: $SCHEMA"

    run_db2_query "$DB" "
      SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
      FROM $SCHEMA.IBMQREP_SENDQUEUES
    "

    run_db2_query "$DB" "
      SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
      FROM $SCHEMA.IBMQREP_RECVQUEUES
    "
  done

done

echo ""
echo "=== Done ==="

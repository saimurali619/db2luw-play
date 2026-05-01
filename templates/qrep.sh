#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo "Current running ASN processes (for reference):"
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo ""

DB2PROFILE=~/sqllib/db2profile

if [ ! -f "$DB2PROFILE" ]; then
  echo "ERROR: db2profile not found at $DB2PROFILE"
  exit 1
fi

# Function: connect → query → disconnect (clean and safe)
run_db2_query() {
  DBNAME="$1"
  SQL="$2"

  . "$DB2PROFILE"

  db2 connect to "$DBNAME" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "  ❌ Failed to connect to $DBNAME"
    return 1
  fi

  OUTPUT=$(db2 -x "$SQL" 2>&1)
  RC=$?

  db2 connect reset > /dev/null 2>&1

  if [ $RC -ne 0 ]; then
    echo "  ❌ DB2 error:"
    echo "$OUTPUT"
    return 1
  fi

  # Clean output
  echo "$OUTPUT" | sed '/^$/d' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Load profile for DB list
. "$DB2PROFILE"

DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo "ERROR: No local databases found in DB directory."
  exit 1
fi

echo "Found local databases: $DBS"
echo ""

for DB in $DBS; do
  echo "--------------------------------------------------"
  echo "DATABASE: $DB"

  # DEBUG: confirm tables exist
  echo "  DEBUG: Q Rep tables in this DB:"
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

  echo "$SCHEMAS" | while IFS= read -r SCHEMA; do
    [ -z "$SCHEMA" ] && continue

    echo "  Q Rep schema: $SCHEMA"

    # APPLY
    echo "    → APPLY config:"
    run_db2_query "$DB" "
      SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
      FROM $SCHEMA.IBMQREP_SENDQUEUES
    "

    # CAPTURE
    echo "    → CAPTURE config:"
    run_db2_query "$DB" "
      SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
      FROM $SCHEMA.IBMQREP_RECVQUEUES
    "
  done

done

echo ""
echo "=== Done ==="
